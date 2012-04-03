package Sojolicious::Oro;
use strict;
use warnings;

use feature 'state';
use Carp qw/carp croak/;
our @CARP_NOT;

# Todo: join: do not automatically assume '*' fields.
# Todo: Support all string operators with [a-z]+.
# Todo: Create, release, and rollback savepoints as private methods
#       so different drivers can handle them differently.

# Database connection
use DBI;

# Defaults to 500 for SQLITE_MAX_COMPOUND_SELECT
use constant MAX_COMP_SELECT => 500;

# Regex for function values
our $FUNCTION_REGEX = qr/[a-zA-Z0-9]+\([^\)]*\)?/;
our $AS_REGEX       = qr/(?::[-_a-zA-Z0-9]+)/;
our $OP_REGEX       = qr/^(?i:
                            (?:[\<\>\!=]?\=?)|<>|
                            (?:!|not[_ ])?
                            (?:match|like|glob|regex|between)|
			    (?:eq|ne|[gl][te])
                          )$/x;
our $KEY_REGEX      = qr/[_0-9a-zA-Z]/;

# Constructor
sub new {
  my $class = shift;
  my ($self, %param);

  # SQLite - one parameter
  if (@_ == 1) {
    @param{qw/driver file/} = ('SQLite', shift);
  }

  # SQLite - two parameter
  elsif (@_ == 2 && ref $_[1] && ref $_[1] eq 'CODE') {
    @param{qw/driver file init/} = ('SQLite', @_);
  }

  # Hash
  else {
    %param = @_;
  };

  # Init by default
  @param{qw/created in_txn last_sql/} = (0, 0, '');

  my $pwd = delete $param{password};

  # Is SQLite
  if (!exists $param{driver} || $param{driver} eq 'SQLite') {

    # Load driver
    require Sojolicious::Oro::SQLite;

    # Get driver specific handle
    $self = Sojolicious::Oro::SQLite->new( %param );
  };

  # No database created
  return unless $self;

  # Connection identifier (for _password)
  $self->{_id} = "$self";

  # Set password securely
  $self->_password($pwd) if $pwd;

  # Connect to database
  $self->_connect or croak 'Unable to connect to database';

  # Release callback
  my $cb = $param{init} if $param{init} && (ref $param{init} || '') eq 'CODE';
  $cb->($self) if $cb;

  # Savepoint array
  # First element is a counter
  $self->{savepoint} = [1];

  # Return Oro instance
  $self;
};


# New table object
sub table {
  my $self = shift;

  my %param;
  # Joined table
  if (ref($_[0])) {
    $param{table} = [ _join_tables( shift(@_) ) ];
  }

  # Table name
  else {
    $param{table} = shift;
  };

  # Clone parameters
  foreach (qw/dbh created in_txn
              savepoint pid tid
	      dsn/) {
    $param{$_} = $self->{$_};
  };

  $param{_id} = "$self";

  # Bless object with hash
  bless \%param, ref $self;
};


# Database handle
# Based on DBIx::Connector
sub dbh {
  my $self = shift;

  # Store new database handle
  return ($self->{dbh} = shift) if $_[0];

  return $self->{dbh} if $self->{in_txn};

  state $c = 'Unable to connect to database';

  # Check for thread id
  if (defined $self->{tid} && $self->{tid} != threads->tid) {
    return $self->_connect or croak $c;
  }

  # Check for process id
  elsif ($self->{pid} != $$) {
    return $self->_connect or croak $c;
  }

  elsif ($self->{dbh}->{Active}) {
    return $self->{dbh};
  };

  # Return handle if active
  return $self->_connect or croak $c;
};


# Last executed SQL
sub last_sql {
  $_[0]->{last_sql} || 'empty';
};


# Database driver
sub driver { '' };


# Database was just created
sub created {
  my $self = shift;

  # Creation state is 0
  return 0 unless $self->{created};

  # Check for thread id
  if (defined $self->{tid} && $self->{tid} != threads->tid) {
    return ($self->{created} = 0);
  }

  # Check for process id
  elsif ($self->{pid} != $$) {
    return ($self->{created} = 0);
  };

  # Return creation state
  return 1;
};


# Insert values to database
sub insert {
  my $self  = shift;

  # Get table name
  my $table = _table_name($self, \@_) or return;

  # No parameters
  return unless $_[0];

  # Single insert
  if (ref($_[0]) eq 'HASH') {

    # Param
    my %param = %{ shift(@_) };

    # Create insert arrays
    my (@keys, @values);
    while (my ($key, $value) = each %param) {
      next unless $key =~ /^[_0-9a-zA-Z]+$/;
      push(@keys,   $key);
      push(@values, $value);
    };

    # Create insert string
    my $sql = 'INSERT INTO ' . $table .
      ' (' . join(', ', @keys) . ') VALUES (' . _q(\@keys) . ')';

    # Prepare and execute
    return scalar $self->prep_and_exec( $sql, \@values );
  }

  # Multiple inserts
  elsif (ref($_[0]) eq 'ARRAY') {

    return unless $_[1];

    my @keys = @{ shift(@_) };

    # Default values
    my @default = ();

    # Check if keys are defaults
    my $i = 0;
    my @default_keys;
    while ($keys[$i]) {

      # No default - next
      $i++, next unless ref $keys[$i];

      # Has default value
      my ($key, $value) = @{ splice( @keys, $i, 1) };
      push(@default_keys, $key);
      push(@default, $value);
    };

    # Unshift default keys to front
    unshift(@keys, @default_keys);

    my $sql = 'INSERT INTO ' . $table . ' (' . join(', ', @keys) . ') ';
    my $union = 'SELECT ' . _q(\@keys);

    # Maximum bind variables
    my $max = (MAX_COMP_SELECT / @keys) - @keys;

    if (scalar @_ <= $max) {

      # Add data unions
      $sql .= $union . ((' UNION ' . $union) x ( scalar(@_) - 1 ));

      # Prepare and execute with prepended defaults
      return $self->prep_and_exec(
	$sql,
	[ map { (@default, @$_); } @_ ]
      );
    }

    # More than SQLite MAX_COMP_SELECT insertions
    else {

      my ($rv, @v_array);
      my @values = @_;

      # Start transaction
      $self->txn(
	sub {
	  while (@v_array = splice(@values, 0, $max - 1)) {

	    # Delete undef values
	    @v_array = grep($_, @v_array) unless @_;

	    # Add data unions
	    my $sub_sql = $sql . $union .
	      ((' UNION ' . $union) x ( scalar(@v_array) - 1 ));

	    # Prepare and execute
	    my $rv_part = $self->prep_and_exec(
	      $sub_sql,
	      [ map { (@default, @$_); } @v_array ]
	    );

	    # Rollback transaction
	    return -1 unless $rv_part;
	    $rv += $rv_part;
	  };

	}) or return;

      # Everything went fine
      return $rv;
    };
  };

  # Unknown query
  return;
};


# Update existing values in the database
sub update {
  my $self  = shift;

  # Get table name
  my $table = _table_name($self, \@_) or return;

  # No parameters
  return unless $_[0];

  # Get pairs
  my ($pairs, $values) = _get_pairs( shift(@_) );

  # Nothing to update
  return unless @$pairs;

  # No arrays or operators allowed
  return unless $pairs ~~ /^$KEY_REGEX+ +(?:=|IS)/o;

  # Set undef to null
  my @pairs = map { $_ =~ s/ IS NULL$/= NULL/; $_ } @$pairs;

  # Generate sql
  my $sql = 'UPDATE ' . $table . ' SET ' . join(', ', @pairs);

  # Condition
  if ($_[0]) {
    my ($cond_pairs, $cond_values) = _get_pairs( shift(@_) );

    # No conditions given
    if (@$cond_pairs) {

      # Append condition
      $sql .= ' WHERE ' . join(' AND ', @$cond_pairs);

      # Append values
      push(@$values, @$cond_values);
    };
  };

  # Prepare and execute
  my $rv = $self->prep_and_exec($sql, $values);

  # Return value
  return (!$rv || $rv eq '0E0') ? 0 : $rv;
};


# Select from table
sub select {
  my $self  = shift;

  # Get table object
  my ($tables, $fields, $join_pairs, $treatment) =
    _table_obj($self, \@_);

  my @pairs = @$join_pairs;

  # Fields to select
  if ($_[0] && ref($_[0]) eq 'ARRAY') {

    # Not allowed for join selects
    return if $fields->[0];

    ($fields, $treatment) = _fields($tables->[0], shift(@_) );

    $fields = [ $fields ];
  };

  # Default
  $fields->[0] ||= '*';

  # Create sql query
  my $sql = join(', ', @$fields) . ' FROM ' . join(', ', @$tables);

  # Append condition
  my @values;

  my $cond;
  if (($_[0] && ref($_[0]) eq 'HASH') || @$join_pairs) {

    # Condition
    my ($pairs, $values, $prep);
    if ($_[0] && ref($_[0]) eq 'HASH') {
      ($pairs, $values, $prep) = _get_pairs( shift(@_) );
      push(@values, @$values);

      # Add to pairs
      push(@pairs, @$pairs) if $pairs->[0];
    };

    # Add where clause
    $sql .= ' WHERE ' . join(' AND ', @pairs) if @pairs;

    # Add distinct information
    if ($prep) {
      $sql = 'DISTINCT ' . $sql if delete $prep->{'distinct'};

      # Apply restrictions
      $sql .= _restrictions($prep, \@values);
    };
  };

  # Prepare and execute
  my ($rv, $sth) = $self->prep_and_exec('SELECT ' . $sql, \@values);

  # No statement created
  return unless $sth;

  # Prepare treatments
  my (@treatment, %treatsub);
  if ($treatment) {
    @treatment = keys %$treatment;
    foreach (@treatment) {
      $treatsub{$_} = shift(@{$treatment->{$_}});
    };
  };

  # Release callback
  if ($_[0] && ref $_[0] && ref $_[0] eq 'CODE' ) {
    my $cb = shift;

    # Iterate through dbi result
    my $row;
    while ($row = $sth->fetchrow_hashref) {

      # Treat result
      if ($treatment) {

	# Treat each treatable row value
	foreach (@treatment) {
	  $row->{$_} = $treatsub{$_}->(
	    $row->{$_}, @{$treatment->{$_}}
	  ) if $row->{$_};
	};
      };

      # Finish if callback returns -1
      my $rv = $cb->($row);
      last if $rv && $rv == -1;
    };

    # Finish statement
    $sth->finish;
    return;
  };

  # Return array ref
  return $sth->fetchall_arrayref({}) unless $treatment;

  # Create array ref
  my $result = $sth->fetchall_arrayref({});

  # Treat each row
  foreach my $row (@$result) {

    # Treat each treatable row value
    foreach (@treatment) {
      $row->{$_} = $treatsub{$_}->(
	$row->{$_}, @{$treatment->{$_}}
      ) if $row->{$_};
    };
  };

  # Return result
  return $result;
};


# Load one line
sub load {
  my $self  = shift;
  my @param = @_;

  # Has a condition
  if ($param[-1] &&
	ref($param[-1]) &&
	  ref($param[-1]) eq 'HASH') {
    $param[-1]->{-limit} = 1;
  }

  # Has no condition yet
  else {
    push(@param, { -limit => 1 });
  };

  # Select with limit
  my $row = $self->select(@param);

  # Error or not found
  return unless $row;

  # Return row
  return $row->[0];
};


# Delete entry
sub delete {
  my $self  = shift;

  # Get table name
  my $table = _table_name($self, \@_) or return;

  # Build sql
  my $sql = 'DELETE FROM ' . $table;

  # Condition
  my ($pairs, $values, $prep, $secure);
  if ($_[0]) {

    # Add condition
    ($pairs, $values, $prep) = _get_pairs( shift(@_) );

    # Add where clause to sql
    $sql .= ' WHERE ' . join(' AND ', @$pairs) if @$pairs || $prep;

    # Apply restrictions
    $sql .= _restrictions($prep, $values) if $prep;
  };

  # Execute deletion
  my $rv = $self->prep_and_exec($sql, $values);

  # Return value
  return (!$rv || $rv eq '0E0') ? 0 : $rv;
};


# Update or insert a value
sub merge {
  my $self  = shift;

  # Get table name
  my $table = _table_name($self, \@_) or return;

  my %param = %{ shift( @_ ) };
  my %cond  = $_[0] ? %{ shift( @_ ) } : ();

  # Prefix with table if necessary
  my @param = ( \%param, \%cond );
  unshift(@param, $table) unless $self->{table};

  my $rv;
  $self->txn(
    sub {

      # Update
      $rv = $self->update( @param );
      return 1 if $rv;

      # Delete all element conditions
      delete $cond{$_} foreach grep( ref( $cond{$_} ), keys %cond);

      # Insert
      @param = ( { %param, %cond } );
      unshift(@param, $table) unless $self->{table};
      $rv = $self->insert(@param) or return -1;

    }) or return;

  # Return value is bigger than 0
  return $rv if $rv && $rv > 0;

  return;
};


# Count results
sub count {
  my $self  = shift;

  # Init arrays
  my ($tables, $fields, $join_pairs, $treatment) =
    _table_obj($self, \@_);
  my @pairs = @$join_pairs;

  # Build sql
  my $sql = 'SELECT ' . join(', ', 'count(*)', @$fields) .
            ' FROM '  . join(', ', @$tables);

  # Get conditions
  my ($pairs, $values);
  if ($_[0]) {
    ($pairs, $values) = _get_pairs( shift(@_) );
    push(@pairs, @$pairs) if $pairs->[0];
  };

  # Add where clause
  $sql .= ' WHERE ' . join(' AND ', @pairs) if @pairs;
  $sql .= ' LIMIT 1';

  # Prepare and execute
  my ($rv, $sth) = $self->prep_and_exec($sql, $values || []);

  # Return value is empty
  return 0 if !$rv || $rv ne '0E0';

  # Return count
  my $count = $sth->fetchrow_arrayref->[0];
  $sth->finish;
  return $count;
};


# Prepare and execute
sub prep_and_exec {
  my ($self, $sql, $values, $cached) = @_;
  my $dbh = $self->dbh;

  # Last sql command
  $self->{last_sql} = $sql;

  # Prepare
  my $sth =
    $cached ? $dbh->prepare_cached( $sql ) :
      $dbh->prepare( $sql );

  # Check for errors
  if ($dbh->err) {

    if (index($dbh->errstr, 'database') <= 0) {
      carp $dbh->errstr . ' in "' . $sql . '"';
      return;
    };

    # Retry with reconnect
    $dbh = $self->_connect;

    $sth =
      $cached ? $dbh->prepare_cached( $sql ) :
	$dbh->prepare( $sql );

    if ($dbh->err) {
      carp $dbh->errstr . ' in "' . $sql . '"';
      return;
    };
  };

  return unless $sth;

  # Execute
  my $rv = $sth->execute( @$values );

  # Check for errors
  if ($dbh->err) {
    carp $dbh->errstr . ' in "' . $sql . '"';
    return;
  };

  # Return value and statement
  return ($rv, $sth) if wantarray;

  # Return value
  $sth->finish;
  return $rv;
};


# Wrapper for DBI do
sub do {
  $_[0]->{last_sql} = $_[1];
  my $dbh = shift->dbh;
  my (@rv) = $dbh->do( @_ );

  carp $dbh->errstr . ' in "' . $_[0] . '"' if $dbh->err;
  return @rv;
};


# Explain query plan
sub explain {
  my $self = shift;

  # Prepare and execute explain query plan
  my ($rv, $sth) = $self->prep_and_exec(
    'EXPLAIN QUERY PLAN ' . shift, @_
  );

  # Query was not succesfull
  return unless $rv;

  # Create string
  my $string;
  foreach ( @{ $sth->fetchall_arrayref([]) }) {
    $string .= sprintf("%3d | %3d | %3d | %-60s\n", @$_);
  };

  # Return query plan string
  return $string;
};


# Wrap a transaction
sub txn {
  my $self = shift;

  return unless (
    $_[0] && ref($_[0]) eq 'CODE'
  );

  my $dbh = $self->dbh;

  # Outside transaction
  if ($dbh->{AutoCommit}) {

    # Start new transaction
    $dbh->begin_work;

    $self->{in_txn} = 1;

    # start
    my $rv = $_[0]->($self);
    if (!$rv || $rv != -1) {
      $self->{in_txn} = 0;
      $dbh->commit;
      return 1;
    };

    # Rollback
    $self->{in_txn} = 0;
    $dbh->rollback;
    return;
  }

  # Inside transaction
  else {
    $self->{in_txn} = 1;

    # Push savepoint on stack
    my $sp_array = $self->{savepoint};

    # Use PID for concurrent accesses
    my $sp = 'orosp_' . $$ . '_';

    # Use TID for concurrent accesses
    $sp .= threads->tid . '_' if $self->{tid};

    $sp .= $sp_array->[0]++;

    # Push new savepoint to array
    push(@$sp_array, $sp);

    # Start transaction
    $self->do('SAVEPOINT ' . $sp);

    # Run wrap actions
    my $rv = $_[0]->($self);

    # Pop savepoint from stack
    my $last_sp = pop(@$sp_array);
    if ($last_sp eq $sp) {
      $sp_array->[0]--;
    }

    # Last savepoint does not match
    else {
      carp "Savepoint $sp is not the last savepoint on stack";
    };

    # Commit savepoint
    if (!$rv || $rv != -1) {
      $self->do("RELEASE SAVEPOINT $sp");
      return 1;
    };

    # Rollback
    $self->do("ROLLBACK TO SAVEPOINT $sp");
    return;
  };
};


# Wrapper for DBI last_insert_id
sub last_insert_id {
  shift->dbh->last_insert_id;
};


# Disconnect on destroy
sub DESTROY {
  my $self = shift;

  # Check if table is parent
  unless (exists $self->{table}) {

    # No database connection
    return $self unless $self->{dbh};

    # Delete password
    $self->_password(0);

    # Delete cached kids
    my $kids = $self->{dbh}->{CachedKids};
    %$kids = () if $kids;

    # Disconnect
    $self->{dbh}->disconnect unless $self->{dbh}->{Kids};
    $self->{dbh} = undef;
  };

  return $self;
};


# Connect with database
sub _connect {
  my $self = shift;

  die 'No database given' unless $self->{dsn};

  # DBI Connect
  my $dbh = DBI->connect(
    $self->{dsn},
    $self->{user} // undef,
    $self->_password,
    {
      PrintError     => 0,
      RaiseError     => 0,
      AutoCommit     => 1,
      @_
    });

  # Unable to connect to database
  unless ($dbh) {
    carp $DBI::errstr;
    return;
  };

  # Store database handle
  $self->{dbh} = $dbh;

  # Save process id
  $self->{pid} = $$;

  # Save thread id
  $self->{tid} = threads->tid if $INC{'threads.pm'};

  return $dbh;
};


# Password closure should prevent accidentally overt passwords
{
  # Password hash
  my %pwd;

  # Password method
  sub _password {
    my $id = shift()->{_id};
    my $pwd_set = shift;

    my ($this) = caller(0);

    # Request only allowed in this namespace
    return unless index(__PACKAGE__, $this) == 0;

    # Return password
    unless (defined $pwd_set) {
      return $pwd{$id};
    }

    # Delete password
    unless ($pwd_set) {
      delete $pwd{$id};
    }

    # Set password
    else {

      # Password can only be set on construction
      for ((caller(1))[3]) {
	m/::new$/ or return;
	index(__PACKAGE__, $_) or return;
	!$pwd{$id} or return;
	$pwd{$id} = $pwd_set;
      };
    };
  };
};


# Get table name
sub _table_name {
  my $self = shift;

  # Table name
  my $table;
  unless (exists $self->{table}) {
    return shift(@{$_[0]}) unless ref $_[0]->[0];
  }

  # Table object
  else {
    # Join table object not allowed
    return $self->{table} unless ref $self->{table};
  };

  return;
};


# Get table object
sub _table_obj {
  my $self = shift;

  my $tables;
  my ($fields, $pairs) = ([], []);

  # Not a table object
  unless (exists $self->{table}) {

    my $table = shift( @{ shift(@_) } );

    # Table name as a string
    unless (ref $table) {
      $tables = [ $table ];
    }

    # Join tables
    else {
      return _join_tables( $table );
    };
  }

  # A table object
  else {

    # joined table
    if (ref $self->{table}) {
      return @{ $self->{table} };
    }

    # Table name
    else {
      $tables = [ $self->{table} ];
    };
  };

  return ($tables, $fields, $pairs);
};


# Join tables
sub _join_tables {
  my @join   = @{ shift @_ };

  my (@tables, @fields, @pairs, $treatment);
  my %marker;

  # Parse table array
  while (@join) {

    # Table name
    my $table = shift @join;
    push(@tables, $table);

    my $ref;
    if ($ref = ref($join[0])) {

      # Field array
      if ($ref eq 'ARRAY') {
	# Automatically prepend table and, if not given, alias
	(my $fields, $treatment) =
	  _fields(
	    $table,
	    [ map {
	      $table . '.' .
		((index($_, ':') >= 0 || ref $_) ? $_ : $_ . ':' . $_)
	      } @{ shift @join } ]);

	push(@fields, $fields);
      };

      # Marker hash reference
      if (ref $join[0] && ref $join[0] eq 'HASH') {
	my $hash = shift @join;

	# Add database fields to marker hash
	while (my ($key, $value) = each %$hash) {
	  my $array = ($marker{$value} //= []);
	  push(@$array, $table . '.' . $key);
	};
      };
    };
  };

  # Create condition pairs based on markers
  foreach my $fields (values %marker) {
    my $field = shift(@$fields);
    foreach (@$fields) {
      push(@pairs, $field . ' = ' . $_ );
    };
  };

  # Return join initialised values
  return (\@tables, \@fields, \@pairs, $treatment);
};


# Get pairs and values
sub _get_pairs ($) {
  my (@pairs, @values, %prep);

  while (my ($key, $value) = each %{$_[0]}) {
    next unless $key =~ qr/^-?$KEY_REGEX+$/o;

    # Restriction of the result set
    if (index($key, '-') == 0) {
      $key = lc($key);

      # Order restriction
      if ($key =~ /^-order(?:_by)?$/i) {

	$prep{order} =
	  join(', ',
	       # Make descending if field has minus prefix
	       map {
		 if (index($_, '-') == 0) {
		   $_ = substr($_, 1) . ' DESC';
		 }; $_;
	       }

	       # Grep all valid values
	       grep(
		 /^(?:-?[a-zA-Z\.]+|$FUNCTION_REGEX)$/o,
		 (ref($value) ? @$value : $value)
	       )
	     );
      }

      # Limit and Offset restriction
      elsif ($key ~~ ['-limit', '-offset', '-distinct']) {
	$prep{substr($key,1)} = $value if $value =~ /^\d+$/;
      };
    }

    # NULL value
    elsif (!defined $value) {
      push(@pairs, $key . ' IS NULL');
    }

    # Array or Hash
    elsif (ref($value)) {

      # Element of
      if (ref($value) eq 'ARRAY') {
	push (@pairs,
	      $key . ' IN (' . _q($value) . ')' );
	push(@values, @$value);
      }

      # Operators
      elsif (ref($value) eq 'HASH') {
	while (my ($op, $val) = each %$value) {
	  if ($op =~ $OP_REGEX) {
	    for ($op) {

	      # Uppercase
	      $_ = uc;

	      # Translate negation
	      s/^!(?=[MLGRB])/NOT /;
	      s/^NOT_/NOT /;

	      # Translate literal compare operators
	      tr/GLENTQ/><=!/d if $_ =~ /(?:[GL][TE]|NE|EQ)/i;
	    };

	    # Simple operator
	    if (index($op, 'BETWEEN') < 0) {
	      push (@pairs, $key . ' ' . $op . ' ?');
	      push(@values, $val);
	    }

	    # Between operator
	    elsif (ref $val && ref $val eq 'ARRAY') {
	      push (@pairs, $key . ' ' . $op . ' ? AND ?');
	      push(@values, $val->[0], $val->[1]);
	    };
	  };
	};
      };
    }

    # Equality
    else {
      push(@pairs,  $key . ' = ?');
      push(@values, $value);
    };
  };

  return (\@pairs, \@values, keys %prep ? \%prep : undef);
};


# Get fields
sub _fields ($$) {
  my $table = shift;

  my %treatment;

  my @fields;
  foreach (@{$_[0]}) {

    # Ordinary String
    unless (ref $_) {
      push(@fields, $_) if /^(?:(?:[\*\.\w]+|$FUNCTION_REGEX))$AS_REGEX?$/o,
    }

    # Treatment
    elsif (ref $_ eq 'ARRAY') {
      my ($sub, $alias) = @$_;
      my ($sql, $inner_sub) = $sub->($table);
      ($sql, $inner_sub, my @param) = $sql->($table) if ref $sql;

      $treatment{ $alias } = [$inner_sub, @param ] if $inner_sub;
      push(@fields, $sql . ':' . $alias);
    };
  };

  my $fields = join(', ', @fields);

  # Return if no alias fields exist
  if (index($fields, ':') < 0 && index($fields, '.') < 0) {
    return $fields;
  };

  # Join with alias fields
  (join(', ',
	map {
	  if ($_ =~ /^(.+?):([^:"]+?)$/) {
	    $1 . ' AS "' . $2 . '"'
	  } elsif ($_ =~ /^(?:.+?)\.(?:[^\.]+?)$/) {
	    my $alias = $_;
	    $alias =~ s/[\"\$\@\#\.\s]/_/g;
	    $_ . ' AS "' . lc $alias . '"';
	  } else {
	    $_
	  }
	} @fields),
   %treatment ? \%treatment : undef);
};


# Restrictions
sub _restrictions ($$) {
  my ($prep, $values) = @_;
  my $sql = '';

  # Order restriction
  if ($prep->{order}) {
    $sql .= ' ORDER BY ' . $prep->{order};
  };

  # Limit restriction
  if ($prep->{limit}) {
    $sql .= ' LIMIT ?';
    push(@$values, $prep->{limit});
  };

  # Offset restriction
  if (defined $prep->{offset}) {
    $sql .= ' OFFSET ?';
    push(@$values, $prep->{offset});
  };

  $sql;
};


# Questionmark string
sub _q ($) {
  join(', ', split('', '?' x scalar( @{$_[0]} )));
};


# Depecated
sub update_or_insert {
  carp 'update_or_insert() is deprecated in favor of merge()';
  shift->merge(@_);
};


# Deprecated
sub transaction {
  carp 'transaction() is deprecated in favor of txn()';
  shift->txn(@_);
};

1;

__END__

=pod

=head1 NAME

Sojolicious::Oro - Simple database accessor


=head1 SYNOPSIS

  use Sojolicious::Oro;

  my $oro = Sojolicious::Oro->new('file.sqlite');
  if ($oro->created) {
    $oro->do(
    'CREATE TABLE Person (
        id    INTEGER PRIMARY KEY,
        name  TEXT NOT NULL,
        age   INTEGER
     )'
    );
  };
  $oro->insert(Person => { name => 'Peter'});
  my $john = $oro->load(Person => { id => 4 });

  my $person = $oro->table('Person');
  my $peters = $person->select({ name => 'Peter' });

=head1 DESCRIPTION

L<Sojolicious::Oro> is a simple database accessor that provides
basic functionalities to work with simple databases in a web
environment.
For now it is limited to SQLite.
It should be fork- and thread-safe.

=head1 ATTRIBUTES


=head2 C<dbh>

  my $dbh = $oro->dbh;
  $oro->dbh(DBI->connect('...'));

The DBI database handle.


=head2 C<created>

  if ($oro->created) {
    print "This is brand new!";
  };

If the database was created on construction of the handle,
this attribute is true. Otherwise it's false.
In most cases, this is useful to create tables, triggers
and indices.

  if ($oro->created) {
    $oro->txn(sub {

      # Create table
      $oro->do(
        'CREATE TABLE Person (
            id    INTEGER PRIMARY KEY,
            name  TEXT NOT NULL,
            age   INTEGER
        )'
      ) or return -1;

      # Create index
      $oro->do(
        'CREATE INDEX age_i ON Person (age)'
      ) or return -1;
    });
  };

B<This attribute is EXPERIMENTAL and may change without warnings.>


=head2 C<last_sql>

  print $oro->last_sql;

The last executed SQL command.


=head2 C<driver>

  print $oro->driver;

The driver ('SQLite') of the Oro instance.

B<This attribute is EXPERIMENTAL and may change without warnings.>


=head1 METHODS


=head2 C<new>

  $oro = Sojolicious::Oro->new('test.sqlite');
  $oro = Sojolicious::Oro->new('test.sqlite' => sub {
    shift->do(
      'CREATE TABLE Person (
          id    INTEGER PRIMARY KEY,
          name  TEXT NOT NULL,
          age   INTEGER
      )');
  })

Creates a new sqlite database accessor object on the
given filename or in memory, if the filename is ':memory:'.
If the database file does not already exist, it is created.
Accepts an optional callback that is only released, if
the database is newly created. The first parameter of
the callback function is the Oro-object.


=head2 C<insert>

  $oro->insert(Person => { id => 4,
                           name => 'Peter',
                           age => 24 });
  $oro->insert(Person => ['id', 'name'] =>
                         [ 4, 'Peter'], [5, 'Sabine']);

Inserts a new row to a given table for single insertions.
Expects the table name and a hash ref of values to insert.

For multiple insertions, it expects the table name
to insert, an arrayref of the column names and an arbitrary
long array of array references of values to insert.

  $oro->insert(Person => ['prename', [ surname => 'Meier' ]] =>
                         map { [$_] } qw/Peter Sabine Frank/);

For multiple insertions with defaults, the arrayref for column
names can contain array references with a column name and the
default value. This value is inserted for each inserted entry
and especially usefull for n:m relation tables.


=head2 C<update>

  my $rows = $oro->update(Person => { name => 'Daniel' },
                                    { id   => 4 } );

Updates values of an existing row of a given table.
Expects the table name to update, a hash ref of values to update,
and optionally a hash ref with conditions, the rows have to fulfill.
In case of scalar values, identity is tested. In case of array refs,
it is tested, if the field is an element of the set.
Returns the number of rows affected.


=head2 C<merge>

  $oro->merge(Person => { age  => 29 },
                        { name => 'Daniel' });

Updates values of an existing row of a given table,
otherways inserts them (so called "upsert").
Expects the table name to update or insert, a hash ref of
values to update or insert, and optionally a hash ref with conditions,
the rows have to fulfill.
In case of scalar values, identity is tested. In case of array refs,
it is tested, if the field is an element of the set.
Scalar condition values will be inserted, if the fields do not exist.


=head2 C<select>

  my $users = $oro->select('Person');
  my $users = $oro->select(Person => ['id', 'name']);
  my $users = $oro->select(Person => ['id'] => {
                             age  => 24,
                             name => ['Daniel','Sabine']
                           });
  my $users = $oro->select(Person => ['name:displayName']);

  $oro->select(Person => sub {
                 print $_[0]->{id},"\n";
                 return -1 if $_[0]->{name} eq 'Peter';
               });

  my $age = 0;
  $oro->select('Person' =>
               ['id', 'age'] =>
               { name => { like => 'Dani%' }} =>
               sub {
                 my $user = shift;
                 say $user->{id};
                 $age += $user->{age};
                 return -1 if $age >= 100;
               });


Returns an array ref of hash refs of a given table,
that meets a given condition or releases a callback in this case.
Expects the table name of selection and optionally an array ref
of fields, optionally a hash ref with conditions and restrictions,
the rows have to fulfill, and optionally a callback,
which is released after each row.
If the callback returns -1, the data fetching is aborted.
In case of scalar values, identity is tested for the condition.
In case of array refs, it is tested, if the field is an element of the set.
In case of hash refs, the keys of the hash represent operators to
test with (see below).
Fields can be column names or functions. With a colon you can define
aliases for the field names.

=head3 Operators

When checking with hashrefs, several operators are supported.

  my $users = $oro->select(Person => {
                            name => {
                              like     => '%e%',
                              not_glob => 'M*'
                            },
                            age => {
                              between => [18, 48],
                              ne      => 30
                            }
                          });

Supported operators are '<' ('lt'), '>' ('gt'), '=' ('eq'),
'<=' ('le'), '>=' ('ge'), '!=' ('ne').
String comparison operators like 'like' and similar are supported.
To negate the latter operators you can prepend 'not_'.
The 'between' and 'not_between' operators are special as the expect
a two value array as their operand.
Multiple operators for checking with the same column are allowed.

B<Operators are EXPERIMENTAL and may change without warnings.>

=head3 Restrictions

In addition to conditions, the selection can be restricted by using
three special restriction parameters:

  my $users = $oro->select(Person => {
                             -order    => ['-age','name'],
                             -offset   => 1,
                             -limit    => 5,
                             -distinct => 1
                           });

=over 2

=item C<-order>

Sorts the result set by field names.
Field names can be scalars or array references of field names ordered
by priority.
A leading minus of the field name will use descending order,
otherwise ascending order.

=item C<-limit>

Limits the number of rows in the result set.

=item C<-offset>

Sets the offset of the result set.

=item C<-distinct>

Boolean value. If set to true, only distinct values are returned.

=back

=head3 Joined Tables

Instead of preparing a select on only one table, it's possible to
use any number of tables and perform a simple join:

  $oro->select(
    [
      Person =>    ['name:author', 'age'] => { id => 1 },
      Book =>      ['title'] => { author_id => 1, publisher_id => 2 },
      Publisher => ['name:publisher', 'id:pub_id'] => { id => 2 }
    ] => { author => 'Akron' }
  );

Join-Selects accept an array reference with a sequences of
table names, field array references and optional hash references
containing markers for the join.
Fields can only be column names, functions are not allowed.
With a colon you can define aliases for the field names.
The join marker hash reference has field names as keys
(no aliases!) and numerical markers as values.
Fields with identical markers will have identical content.

A following array reference of fields is not allowed.
After the join table array reference, the optional hash
reference with conditions and restrictions and an optional
callback follow immediately.

B<Joins are EXPERIMENTAL and may change without warnings.>

=head3 Treatments

Sometimes field functions and returned values shall be treated
in a special way.
By handing over subroutines, C<select> as well as C<load> allow
for these treatments.

  my $name = sub {
    return ('name', sub { uc($_[0]) });
  };
  $oro->select(Person => ['age', [ $name => 'name'] ]);

This example returns all values in the 'name' column in uppercase.
Treatments are array references in the field array, with the first
element being a treatment subroutine reference and the second element
being the alias of the column.

The treatment subroutine returns a field value (an SQL string),
optionally an anonymous subroutine that is executed after each
returned value, and optionally an array of values to pass to the inner
subroutine. The first parameter the inner subroutine has to handle,
is the value to treat, following the optional treatment parameters.
The treatment returns the treated value (that does not has to be a string).

Outer subroutines are executed as long as the first value is not a string
value. The only parameter passed to the outer subroutine is the
current table name.

B<Treatments are EXPERIMENTAL and may change without warnings.>

=head2 C<load>

  my $user  = $oro->load(Person, { id => 4 });
  my $user  = $oro->load(Person, ['name'], { id => 4 });
  my $count = $oro->load(Person, ['count(*):persons']);

Returns a single hash ref of a given table,
that meets a given condition.
Expects the table name of selection, an optional array ref of fields
to return and a hash ref with conditions, the rows have to fulfill.
Normally this includes the primary key.
In case of scalar values, identity is tested.
In case of array refs, it is tested, if the field is an element of the set.
Fields can be column names or functions. With a colon you can define
aliases for the field names.


=head2 C<delete>

  my $rows = $oro->delete(Person => { id => 4 });

Deletes rows of a given table, that meet a given condition.
Expects the table name of selection and optionally a hash ref
with conditions and restrictions, the rows have to fulfill.
In case of scalar values, identity is tested for the condition.
In case of array refs, it is tested, if the field is an element of the set.
Restrictions can be applied as with L<select>.
Returns the number of rows that were deleted.


=head2 C<count>

  my $persons = $oro->count('Person');
  my $pauls   = $oro->count('Person' => { name => 'Paul' });

Returns the number of rows of a table.
Expects the table name and a hash ref with conditions,
the rows have to fulfill.


=head2 C<table>

  # Table names
  my $person = $oro->table('Person');
  print $person->count;
  my $person = $person->load({ id => 2 });
  my $persons = $person->select({ name => 'Paul' });
  $person->insert({ name => 'Ringo' });
  $person->delete;

  # Joined tables
  my $books = $oro->table(
    [
      Person =>    ['name:author', 'age:age'] => { id => 1 },
      Book =>      ['title'] => { author_id => 1, publisher_id => 2 },
      Publisher => ['name:publisher', 'id:pub_id'] => { id => 2 }
    ]
  );
  $books->select({ author => 'Akron' });
  print $books->count;

Returns a new C<Sojolicious::Oro> object with a predefined table
or a joined table. Allows to omit the first table argument for the methods
L<select>, L<load>, L<count> and - in case of non-joined-tables -
for L<insert>, L<update>, L<merge>, and L<delete>.
C<table> in conjunction with a joined table can be seen as an "ad hoc view".

B<This method is EXPERIMENTAL and may change without warnings.>

=head2 C<prep_and_exec>

  my ($rv, $sth) = $oro->prep_and_exec(
    'SELECT ? FROM Person', ['name'], 'cached'
  );

  if ($rv) {
    my $row;
    while ($row = $sth->fetchrow_hashref) {
      print $row->{name};
      if ($name eq 'Fry') {
        $sth->finish;
        last;
      };
    };
  };

Prepare and execute an SQL statement with all checkings.
Returns the return value (on error C<false>, otherwise C<true>,
e.g. the number of modified rows) and - in an array context -
the statement handle.
Accepts the SQL statement, parameters for binding in an array
reference and optionally a boolean value, if the prepared
statement should be cached.


=head2 C<explain>

  print $oro->explain(
    'SELECT ? FROM Person', ['name']
  );

Returns the query plan for a given query as a line-breaked string.

B<This method is EXPERIMENTAL and may change without warnings.>


=head2 C<txn>

  $oro->txn(
    sub {
      foreach (1..100) {
        $oro->insert(Person => { name => 'Peter'.$_ }) or return -1;
      };
      $oro->delete(Person => { id => 400 });

      $oro->txn(
        sub {
          $oro->insert('Person' => { name => 'Fry' }) or return -1;
        }) or return -1;
    });

Allows to wrap transactions.
Expects an anonymous subroutine containing all actions.
If the subroutine returns -1, the transactional data will be omitted.
Otherwise the actions will be released.
Transactions established with this method can be securely nested
(although inner transactions may not be true transactions depending
on the driver).


=head2 C<last_insert_id>

  my $id = $oro->last_insert_id;

Returns the globally last inserted id regarding to the database connection.


=head2 C<do>

  $oro->do(
    'CREATE TABLE Person (
        id   INTEGER PRIMARY KEY,
        name TEXT NOT NULL,
     )');

Executes SQL code.
This is a wrapper for the DBI C<do()> method (but fork- and thread-safe).


=head1 DEPENDENCIES

L<Carp>,
L<DBI>,
L<DBD::SQLite>,
L<File::Path>,
L<File::Basename>.


=head1 ACKNOWLEDGEMENT

Partly inspired by L<ORLite>, written by Adam Kennedy.
Some code is based on L<DBIx::Connector>, written by David E. Wheeler.
Without me knowing (it's a shame!), some of the concepts are quite similar
to L<SQL::Abstract>, written by Nathan Wiger et al.


=head1 AVAILABILITY

  https://github.com/Akron/Sojolicious


=head1 COPYRIGHT AND LICENSE

Copyright (C) 2011-2012, Nils Diewald.

This program is free software, you can redistribute it
and/or modify it under the same terms as Perl.

=cut
