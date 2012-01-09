package Sojolicious::Oro;
use strict;
use warnings;
use feature 'state';
use Carp qw/carp croak/;

our $VERSION = '0.01';

# Database connection
use DBI;
use DBD::SQLite;

# Find and create database file
use File::Path;
use File::Basename;

# Defaults to 500 for SQLITE_MAX_COMPOUND_SELECT
use constant MAX_COMP_SELECT => 500;

# Default limit for pager
our $PAGER_LIMIT = 10;

# Regex for function values
our $FUNCTION_REGEX = qr/[a-zA-Z0-9]+\([^\)]*\)?/;
our $AS_REGEX       = qr/(?::[a-zA-Z0-9]+)/;

# Constructor
sub new {
  my ($class, $file, $cb) = @_;

  # Bless object with hash
  my $self = bless {
    created => 0,
    in_txn  => 0,
    table   => '__UNKNOWN__'
  }, $class;

  # Store filename
  $self->file($file);

  # No database defined
  croak 'No database defined' unless $file;

  # Create path for file - based on ORLite
  unless (-f $file) {
    $self->{created} = 1;

    my $dir = File::Basename::dirname($file);
    unless ( -d $dir ) {
      File::Path::mkpath( $dir, { verbose => 0 } );
    };
  };

  # Connect to database
  $self->_connect or croak 'Unable to connect to database';

  # Release callback
  $cb->($self) if $cb && ref($cb) eq 'CODE';

  # Savepoint array
  # First element is a counter
  $self->{savepoint} = [1];

  return $self;
};


# New table object
sub table {
  my $self = shift;

  my %param = (
    table   => shift
  );

  # Clone parameters
  foreach (qw/dbh created file
              in_txn savepoint pid tid/) {
    $param{$_} = $self->{$_};
  };

  # Bless object with hash
  bless \%param, ref($self);
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


# File of database
sub file {
  return $_[0]->{file} unless $_[1];
  $_[0]->{file} = $_[1];
};


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
  my $table = ref($_[0]) ? $self->{table} : shift;

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
          ' (' . join(', ', @keys) . ')' .
	  ' VALUES' .
	  ' (' . _q(\@keys) . ')';

    # Prepare and execute
    return $self->prep_and_exec( $sql, \@values );
  }

  # Multiple inserts
  elsif (ref($_[0]) eq 'ARRAY') {

    return unless $_[1];

    my @keys = @{ shift(@_) };

    my $sql = 'INSERT INTO ' . $table . ' (' . join(', ', @keys) . ') ';
    my $union = ' SELECT ' . _q(\@keys). ' ';

    if (scalar @_ <= MAX_COMP_SELECT) {

      # Add data unions
      $sql .= $union . ((' UNION ' . $union) x ( scalar(@_) - 1 ));

      # Prepare and execute
      return $self->prep_and_exec($sql, [ map( @$_,  @_ ) ]);
    }

    # More than MAX_COMP_SELECT insertions
    else {

      my ($rv, @v_array);
      my @values = @_;

      # Start transaction
      $self->txn(
	sub {
	  while (@v_array = splice(@values, 0, MAX_COMP_SELECT - 1)) {

	    # Delete undef values
	    @v_array = grep($_, @v_array) unless @_;

	    # Add data unions
	    my $sub_sql = $sql . $union .
	      ((' UNION ' . $union) x ( scalar(@v_array) - 1 ));

	    # Prepare and execute
	    my $rv_part = $self->prep_and_exec(
	      $sub_sql,
	      [ map( @$_,  @v_array ) ]
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
  my $table = ref($_[0]) ? $self->{table} : shift;

  # No parameters
  return unless $_[0];

  my ($pairs, $values) = _get_pairs( shift(@_) );

  # Nothing to update
  return unless @$pairs;

  my $sql = 'UPDATE ' . $table . ' SET ' . join(', ', @$pairs);

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
  my $table = !$_[0] || ref($_[0]) ? $self->{table} : shift;

  # Fields to select
  my $fields = '*';
  if ($_[0] && ref($_[0]) eq 'ARRAY') {
    $fields = _fields( shift(@_) );
  };

  # Create sql query
  my $sql = 'SELECT ' . $fields . ' FROM ' . $table;

  # Append condition
  my @values;

  if ($_[0] && ref($_[0]) eq 'HASH') {
    my ($pairs, $values, $prep) = _get_pairs( shift(@_) );

    if (@$pairs) {
      $sql .= ' WHERE ' . join(' AND ', @$pairs);
      push(@values, @$values);
    };

    # Apply restrictions
    $sql .= _restrictions($prep, \@values) if $prep;
  };

  # Prepare and execute
  my ($rv, $sth) = $self->prep_and_exec($sql, \@values);

  return unless $sth;

  # Release callback
  if ($_[0] && ref($_[0]) eq 'CODE') {

    # Iterate through dbi result
    my $row;
    while ($row = $sth->fetchrow_hashref) {

      # Finish if callback returns -1
      if ($_[0]->($row) == -1) {
	last;
      };
    };

    # Finish statement
    $sth->finish;
    return;
  }

  # Return array ref
  else {
    return $sth->fetchall_arrayref({});
  };
};


# Load one line
sub load {
  my $self  = shift;
  my $table = ref($_[0]) ? $self->{table} : shift;

  # Fields to select
  my $fields = '*';
  if ($_[0] && ref($_[0]) && ref($_[0]) eq 'ARRAY') {
    $fields = _fields( shift(@_) );
  };

  # Build sql
  my $sql = 'SELECT ' . $fields . ' FROM ' . $table;

  # Parameters
  my ($pairs, $values);
  if ($_[0]) {
    ($pairs, $values) = _get_pairs( shift(@_) );
    $sql .= ' WHERE ' . join(' AND ', @$pairs);
  };

  $sql .= ' LIMIT 1';

  # Prepare and execute
  my ($rv, $sth) = $self->prep_and_exec($sql, $values || []);

  # No handle
  return {} unless $sth;

  # Retrieve
  my $row = $sth->fetchrow_hashref;
  $sth->finish;
  return $row;
};


# Delete entry
sub delete {
  my $self  = shift;
  my $table = !$_[0] || ref($_[0]) ? $self->{table} : shift;

  # Build sql
  my $sql = 'DELETE FROM ' . $table;

  # With parameters
  my ($pairs, $values, $prep);
  if ($_[0]) {
    ($pairs, $values, $prep) = _get_pairs( shift(@_) );
    $sql .= ' WHERE ' . join(' AND ', @$pairs);

    # Apply restrictions
    $sql .= _restrictions($prep, $values) if $prep;
  };

  # Prepare and execute
  my $rv = $self->prep_and_exec($sql, $values);

  return (!$rv || $rv eq '0E0') ? 0 : $rv;
};


# Update or insert a value
sub merge {
  my $self  = shift;
  my $table = ref($_[0]) ? $self->{table} : shift;

  my %param = %{ shift( @_ ) };
  my %cond  = $_[0] ? %{ shift( @_ ) } : ();

  my $rv;
  $self->txn(
    sub {

      # Update
      $rv = $self->update($table => \%param, \%cond);
      return 1 if $rv;

      # Delete all element conditions
      delete $cond{$_} foreach grep( ref( $cond{$_} ), keys %cond);

      # Insert
      $rv = $self->insert($table => { %param, %cond }) or return -1;

    }) or return;

  # Return value is bigger than 0
  return $rv if $rv && $rv > 0;

  return;
};


# Count results
sub count {
  my $self  = shift;
  my $table = !$_[0] || ref($_[0]) ? $self->{table} : shift;

  # Build sql
  my $sql = 'SELECT count(*) FROM ' . $table;

  my ($pairs, $values);
  if ($_[0]) {
    ($pairs, $values) = _get_pairs( shift(@_) );
    $sql .= ' WHERE ' . join(' AND ', @$pairs);
  };

  # Prepare and execute
  my ($rv, $sth) = $self->prep_and_exec($sql, $values || []);

  return 0 if !$rv || $rv ne '0E0';

  my $count = $sth->fetchrow_arrayref->[0];
  $sth->finish;

  return $count;
};


# Pager
# Todo: Not fork- and thread-safe
sub pager {
  my $self  = shift;
  my $table = !$_[0] || ref($_[0]) ? $self->{table} : shift;

  # Fields to select
  my $fields = '*';
  if ($_[0] && ref($_[0]) eq 'ARRAY') {
    $fields = _fields( shift(@_) );
  };

  # Create sql query
  my $sql = 'SELECT ' . $fields . ' FROM ' . $table;

  my @values;
  my ($limit, $offset);
  my $prep = {};

  # Append condition
  if ($_[0] && ref($_[0]) eq 'HASH') {
    my ($pairs, $values);
    ($pairs, $values, $prep) = _get_pairs( shift(@_) );

    if (@$pairs) {
      $sql .= ' WHERE ' . join(' AND ', @$pairs);
      push(@values, @$values);
    };
  };

  # Apply restrictions
  $limit  = ($prep->{limit}  //= $PAGER_LIMIT);
  $offset = ($prep->{offset} //= 0);

  $sql .= _restrictions($prep, []);

  # Prepare
  my $dbh   = $self->dbh;
  my $sth;
  eval {
    $sth = $dbh->prepare( $sql );
  };

  # Check for errors
  if ($@) {
    carp $@ . "\nSQL: " . $sql;
    return;
  };

  return unless $sth;

  # return anon subroutine
  return sub {
    my $step = $limit;

    # Optional step parameter
    if ($_[0] && $_[0] =~ /^\d+$/) {
      $step = shift;
    };

    # Execute
    my $rv;
    eval {
      $rv = $sth->execute( @values, $step, $offset );
    };

    # Check for errors
    if ($@) {
      carp $@ . "\nSQL: " . $sql;
      return;
    };

    # Next step
    $offset += $step;

    # Return array ref
    my $rows = $sth->fetchall_arrayref({});
    return @$rows ? $rows : 0
  };
};


# Prepare and execute
sub prep_and_exec {
  my ($self, $sql, $values, $cached) = @_;
  my $dbh = $self->dbh;

  # Prepare
  my $sth;
  eval {
    $sth =
      $cached ? $dbh->prepare_cached( $sql ) :
	$dbh->prepare( $sql );
  };

  # Check for errors
  if ($@) {

    # Retry with reconnect
    $dbh = $self->_connect;

    eval {
      $sth =
	$cached ? $dbh->prepare_cached( $sql ) :
	  $dbh->prepare( $sql );
    };

    if ($@) {
      carp $@ . "\nSQL: " . $sql;
      return;
    };
  };

  return unless $sth;

  # Execute
  my $rv;
  eval {
    $rv = $sth->execute( @$values );
  };

  # Check for errors
  if ($@) {
    carp $@ . "\nSQL: " . $sql;
    return;
  };

  # Return values
  return ($rv, $sth) if wantarray;

  $sth->finish;
  return $rv;
};


# Wrapper for DBI do
sub do {
  shift->dbh->do( @_ );
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
    $self->do('SAVEPOINT '.$sp);

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


# Wrapper for sqlite last_insert_row_id
sub last_insert_id {
  shift->dbh->sqlite_last_insert_rowid;
};


# Disconnect on destroy
sub DESTROY {
  my $self = shift;

  # Check if table is parent
  if ($self->{table} eq '__UNKNOWN__') {

    # No database connection
    return $self unless $self->{dbh};

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

  # DBI Connect
  my $dbh;
  eval {
    $dbh = DBI->connect(
      'dbi:SQLite:' . $self->file,
      undef,
      undef,
      {
	PrintError     => 0,
	RaiseError     => 1,
	AutoCommit     => 1,
	sqlite_unicode => 1
      });
  };

  # Unable to connect to database
  if ($@) {
    carp $@;
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


# Get pairs and values
sub _get_pairs ($) {
  my (@pairs, @values, %prep);

  while (my ($key, $value) = each %{$_[0]}) {
    next unless $key =~ /^-?[_0-9a-zA-Z]+$/;

    # Restriction of the result set
    if (index($key, '-') == 0) {
      $key = lc($key);

      # Order restriction
      if ($key eq '-order') {

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
      elsif ($key ~~ ['-limit', '-offset']) {
	$prep{substr($key,1)} = $value if $value =~ /^\d+$/;
      };
    }

    # NULL value
    elsif (!defined $value) {
      push(@pairs, $key . ' IS NULL');
    }

    # Element of
    elsif (ref($value) && ref($value) eq 'ARRAY') {
      push (@pairs,
	    $key . ' IN (' . _q($value) . ')' );
      push(@values, @$value);
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
sub _fields ($) {

  # Check for valid fields
  my @fields = grep(
    /^(?:(?:[\*\.\w]+|$FUNCTION_REGEX))$AS_REGEX?$/o,
    @{ $_[0] }
  );
  my $fields = join(', ', @fields);

  # Return if no alias fields exist
  if (index($fields, ':') < 0) {
    return $fields;
  };

  # Join with alias fields
  join(', ',
       map {
	 if ($_ =~ /^(.+?):([^:]+?)$/) {
	   $1 . ' AS ' . $2
	 } else {
	   $_
	 }
       } @fields);
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

Sojolicious::Oro - Simple SQLite database accessor


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
  $john = $person->load({ id => 4 });

=head1 DESCRIPTION

L<Sojolicious::Oro> is a simple database accessor that provides
basic functionalities to work with really simple databases.
For now it only works with SQLite.
It should be fork- and thread-safe.

=head1 ATTRIBUTES


=head2 C<dbh>

  my $dbh = $oro->dbh;
  $oro->dbh(DBI->connect('...'));

The DBI database handle.


=head2 C<file>

  my $file = $oro->file;
  $oro->file('myfile.sqlite');

The sqlite file of the database.
# This attribute is EXPERIMENTAL.


=head2 C<created>

  if ($oro->created) {
    print "This is brand new!";
  };

If the database was created on construction of the handle,
this attribute is true. Otherwise it's false.
In most cases, this is usefull to create tables, triggers
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
given filename. If the database does not already exist,
it is created.
Accepts an optional callback that is only released, if
the database is newly created.


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
long array of references of values to insert.


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
  $oro->select(Person => sub {
                 print $_[0]->{id},"\n";
                 return -1 if $_[0]->{name} eq 'Peter';
               });
  my $users = $oro->select(Person => ['id', 'name']);
  my $users = $oro->select(Person => ['id'] => {
                             age  => 24,
                             name => ['Daniel','Sabine']
                           });

  my $users = $oro->select(Person => ['name:displayName']);
  $oro->select('Person' =>
               ['id','age'] =>
               { name => 'Daniel' } =>
               sub {
                 my $user = shift;
                 print $user->{id},"\n";
                 return -1 if $user->{name} =~ /^Da/;
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
Fields can be column names or functions. With a colon you can define
aliases for the field names.

In addition to conditions, the selection can be restricted by using
three special restriction parameters:

  my $users = $oro->select(Person => {
                             -order  => ['-age','name'],
                             -offset => 1,
                             -limit  => 5
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

=back

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

  my $person = $oro->table('Person');
  print $person->count;
  my $person = $person->load({ id => 2 });
  my $persons = $person->select({ name => 'Paul' });
  $person->insert({ name => 'Ringo' });
  $person->delete;

Returns a new C<Sojolicious::Oro> object with a predefined table
name. Allows to omit the first table name argument for the methods
L<insert>, L<update>, L<select>, L<merge>, L<delete>, L<load>, and
L<count>.

This method is EXPERIMENTAL and may change without warnings.

=head2 C<prep_and_exec>

  my ($rv, $sth) =
    $oro->prep_and_exec('SELECT ? From Person',
                        ['name'], 'cached');

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
Returns the return value (on error false, otherwise true,
e.g. the number of modified rows) and the statement handle.
Accepts the SQL statement, parameters for binding in an array
reference and optionally a boolean value, if the prepared
statement should be cached.


=head2 C<pager>

  # Construct new pager
  my $pager = $oro->pager(Person => {
                            -offset => 2,
                            -limit  => 3
                          });

  # Loop over pager
  while ($_ = $pager->()) {
    foreach my $row (@$_) {
      print $row->{name}, "\n";
    };
    print "--next page--\n";
  };

Creates an anonymous subroutine for page based looping.
Accepts all parameters as described in L<select>,
except for the optional callback.
The C<-offset> restriction is used for an initial offset,
the C<-limit> restriction is used for step length.
An optional parameter to the subroutine can set the step
length for the next request.
If no step length parameter is given, neither by the
C<-offset> parameter nor the parameter to the subroutine,
the step length defaults to 10.
The return value is identical to L<select>.
If no rows are found, the return value is C<undef>.

This method is EXPERIMENTAL and may change without warnings.

=head2 C<txn>

  $oro->txn(
    sub {
      foreach (1..100) {
        $oro->insert(Person => { name => 'Peter'.$_ }) or return -1;
      };
      $oro->delete(Person => { id => 400 });

      $oro->txn(
        sub {
          $oro->insert('Person' => { name => 'Fry'}) or return -1;
        }) or return -1;
    });

Allows to wrap transactions.
Expects an anonymous subroutine containing all actions.
If the subroutine returns -1, the transactional data will be omitted.
Otherwise the actions will be released.
Transactions established with this method can be securely nested.


=head2 C<last_insert_id>

  my $id = $oro->last_insert_id;

Returns the globally last inserted id.


=head2 C<do>

  $oro->do(
    'CREATE TABLE Person (
        id   INTEGER PRIMARY KEY,
        name TEXT NOT NULL,
     )');

Executes SQL code.
This is a Wrapper for the DBI C<do()> method.


=head1 DEPENDENCIES

L<Carp>,
L<DBI>,
L<DBD::SQLite>,
L<File::Path>,
L<File::Basename>.


=head1 ACKNOWLEDGEMENT

Partly inspired by L<ORLite>, written by Adam Kennedy.
Some code is based on L<DBIx::Connector>, written by David E. Wheeler.
Without knowing, some of the concepts are quite similar
to L<SQL::Abstract>, written by.

=head1 AVAILABILITY

  https://github.com/Akron/Sojolicious


=head1 COPYRIGHT AND LICENSE

Copyright (C) 2011, Nils Diewald.

This program is free software, you can redistribute it
and/or modify it under the same terms as Perl.

=cut
