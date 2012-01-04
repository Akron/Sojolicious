package Sojolicious::Oro;
use strict;
use warnings;

# Database connection
use DBI;
use DBD::SQLite;

# Find database file
use File::Path;
use File::Basename;

# Defaults to 500 for SQLITE_MAX_COMPOUND_SELECT
use constant MAX_COMPOUND_SELECT => 500;

# Regex for function values
our $FUNCTION_REGEX = qr/[a-zA-Z]+\([\*\.\w\,]*\)(?::[a-zA-Z]+)?/;

# Default limit for pager
our $PAGER_LIMIT = 10;

# Constructor
sub new {
  my ($class, $file, $cb) = @_;

  # Bless object with hash
  my $self = bless {
    created => 0,
    table   => '__UNKNOWN__'
  }, $class;

  # Store filename
  $self->file($file);

  die 'No database defined' unless $file;

  # Create path for file - based on ORLite
  unless (-f $file) {
    $self->{created} = 1;

    my $dir = File::Basename::dirname($file);
    unless ( -d $dir ) {
      File::Path::mkpath( $dir, { verbose => 0 } );
    };
  };

  # Connect to Database
  my $dbh = DBI->connect(
    "dbi:SQLite:$file",
    undef,
    undef,
    {
      PrintError => 0,
      RaiseError => 1,
    });

  # Store database handle
  $self->{dbh} = $dbh;

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
    table => shift
  );

  # Clone parameters
  foreach (qw/dbh file created savepoint/) {
    $param{$_} = $self->{$_};
  };

  # Bless object with hash
  bless \%param, ref($self);
};


# Database handle
sub dbh {
  return $_[0]->{dbh} unless $_[1];
  $_[0]->{dbh} = $_[1];
};


# File of database
sub file {
  return $_[0]->{file} unless $_[1];
  $_[0]->{file} = $_[1];
};


# Database was just created
sub created {
  $_[0]->{created};
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
	  ' VALUES ' .
	  '(' . _q(\@keys) . ')';

    # Prepare and execute
    my ($rv) = $self->prep_and_exec( $sql, \@values );

    return $rv;
  }

  # Multiple inserts
  elsif (ref($_[0]) eq 'ARRAY') {

    return unless $_[1];

    my @keys = @{ shift(@_) };

    my $sql = 'INSERT INTO ' . $table . ' (' . join(', ', @keys) .') ';
    my $union = ' SELECT ' . _q(\@keys). ' ';

    if (scalar @_ < MAX_COMPOUND_SELECT) {

      # Add data unions
      $sql .= $union . ((' UNION ' . $union) x (scalar(@_) - 1));

      # Prepare and execute
      my ($rv) = $self->prep_and_exec($sql, [ map( @$_,  @_ ) ]);

      return $rv;
    }

    # More than MAX_COMPOUND_SELECT insertions
    else {

      my ($rv, @value_array);
      my @values = @_;

      # Start transaction
      $self->transaction(
	sub {
	  while (@value_array = splice(@values, 0, MAX_COMPOUND_SELECT - 1)) {

	    # Delete undef values
	    @value_array = grep($_, @value_array) unless @_;

	    # Add data unions
	    my $sub_sql = $sql . $union .
	      ((' UNION ' . $union) x (scalar(@value_array) - 1));

	    # Prepare and execute
	    my ($rv_part) = $self->prep_and_exec(
	      $sub_sql,
	      [ map( @$_,  @value_array ) ]
	    );

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

  my $sql = 'UPDATE ' . $table .
            ' SET ' . join(', ', @$pairs);

  if ($_[0]) {
    my ($cond_pairs, $cond_values) = _get_pairs(shift(@_));

    # No conditions given
    if (@$cond_pairs) {

      # Append condition
      $sql .= ' WHERE ' . join(' AND ', @$cond_pairs);

      # Append values
      push(@$values, @$cond_values);
    };
  };

  # Prepare and execute
  my ($rv) = $self->prep_and_exec($sql, $values);

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
	$sth->finish;
	last;
      };
    };
  }

  # Return array ref
  else {
    return $sth->fetchall_arrayref({});
  };

  return;
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

  # Retrieve
  return $sth ? $sth->fetchrow_hashref : {};
};


# Delete entry
sub delete {
  my $self  = shift;
  my $table = !$_[0] || ref($_[0]) ? $self->{table} : shift;

  # Build sql
  my $sql = 'DELETE FROM ' . $table;

  my ($pairs, $values, $prep);

  # With parameters
  if ($_[0]) {
    ($pairs, $values, $prep) = _get_pairs( shift(@_) );
    $sql .= ' WHERE ' . join(' AND ', @$pairs);

    # Apply restrictions
    $sql .= _restrictions($prep, $values) if $prep;
  };

  # Prepare and execute
  my ($rv) = $self->prep_and_exec($sql, $values);

  return (!$rv || $rv eq '0E0') ? 0 : $rv;
};


# Update or insert a value
sub merge {
  my $self  = shift;
  my $table = ref($_[0]) ? $self->{table} : shift;

  my %param = %{ shift( @_ ) };
  my %cond  = $_[0] ? %{ shift( @_ ) } : ();

  my $rv;
  $self->transaction(
    sub {

      # Update
      $rv = $self->update($table, \%param, \%cond);
      return 1 if $rv;

      # Delete all element conditions
      delete $cond{$_} foreach grep( ref( $cond{$_} ), keys %cond);

      # Insert
      $rv = $self->insert($table, { %param, %cond }) or return -1;

    }) or return;

  return $rv if $rv && $rv > 0;

  return;
};


# Temporary
sub update_or_insert {
  warn 'update_or_insert is deprecated in favor of merge';
  shift->merge(@_);
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

  return (!$rv || $rv ne '0E0') ? 0 : $sth->fetchrow_arrayref->[0];
};


# Pager
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
  my $dbh   = $self->{dbh};
  my $sth;
  eval {
    $sth = $dbh->prepare( $sql );
  };

  # Check for errors
  if ($@) {
    warn $@ . "\nSQL: " . $sql;
    return;
  };

  return unless $sth;

  # return anon subroutine
  return sub {
    my $step = shift || $limit;

    # Execute
    my $rv;
    eval {
      $rv = $sth->execute( @values, $step, $offset );
    };

    # Check for errors
    if ($@) {
      warn $@ . "\nSQL: " . $sql;
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
  my $dbh = $self->{dbh};

  # Prepare
  my $sth;
  eval {

    # not cached
    unless ($cached) {
      $sth = $dbh->prepare( $sql );
    }

    # cached
    else {
      $sth = $dbh->prepare_cached( $sql );
    };
  };

  # Check for errors
  if ($@) {
    warn $@ . "\nSQL: " . $sql;
    return;
  };

  return unless $sth;

  # Execute
  my $rv;
  eval {
    $rv = $sth->execute( @$values );
  };

  # Check for errors
  if ($@) {
    warn $@ . "\nSQL: " . $sql;
    return;
  };

  # Return values
  return ($rv, $sth);
};


# Wrapper for DBI do
sub do {
  shift->{dbh}->do( @_ );
};


# Wrap a transaction
sub transaction {
  my $self = shift;

  return unless (
    $_[0] && ref($_[0]) eq 'CODE'
  );

  my $dbh = $self->{dbh};

  # Outside transaction
  if ($dbh->{AutoCommit}) {
    $dbh->begin_work;

    # start
    my $rv = $_[0]->($self);
    if (!$rv || $rv != -1) {
      $dbh->commit;
      return 1;
    };

    # Rollback
    $dbh->rollback;
    return;
  }

  # Inside transaction
  else {

    # Push savepoint on stack
    my $sp_array = $self->{savepoint};

    # Use PID for concurrent accesses
    my $sp = 'orosp_' . $$ . '_' . $sp_array->[0]++;
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
      warn "Savepoint $sp is not the last savepoint on stack";
    };

    # Commit savepoint
    if (!$rv || $rv != -1) {
      $self->do("RELEASE SAVEPOINT $sp");
      return 1;
    };

    # rollback
    $self->do("ROLLBACK TO SAVEPOINT $sp");
    return;
  };
};


# Wrapper for sqlite last_insert_row_id
sub last_insert_id {
  shift->{dbh}->sqlite_last_insert_rowid;
};


# Get pairs and values
sub _get_pairs {
  my (@pairs, @values, %prep);
  while (my ($key, $value) = each %{$_[0]}) {
    next unless $key =~ /^[-_0-9a-zA-Z]+$/;

    # Preparation of the result set
    if (index($key,'-') == 0) {
      $key = lc($key);

      # Limit and Offset restriction
      if ($key ~~ ['-limit', '-offset']) {
	$prep{substr($key,1)} = $value if $value =~ /^\d+$/;
      }

      # Order restriction
      elsif ($key eq '-order') {
	$prep{order} =
	  join(', ',
	       map {
		 if (index($_,'-') == 0) {
		   $_ = substr($_,1). ' DESC';
		 }; $_;
	       }
	       grep(/^(?:[-]?[a-zA-Z\.]+|$FUNCTION_REGEX)$/o,
		    (ref($value) ? @$value : $value)));
      };
      next;
    };

    # Element of
    if (ref($value) && ref($value) eq 'ARRAY') {
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
  my @fields = grep(/^(?:[\*\.\w]+(?::[a-zA-Z]+)?|$FUNCTION_REGEX)$/o,
		    @{ $_[0] });
  my $fields = join @fields;

  # Return if no alias fields exist
  if (index(':', $fields) < 0) {
    return $fields;
  };

  # join with alias fields
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
sub _restrictions {
  my ($prep, $values) = @_;
  my $sql = '';

  # Order restriction
  if ($prep->{order}) {
    $sql .= ' ORDER BY ' . $prep->{order};
  };

  # Limit restriction
  if ($prep->{limit}) {
    $sql .= ' LIMIT ? ';
    push(@$values, $prep->{limit});
  };

  # Offset restriction
  if (defined $prep->{offset}) {
    $sql .= ' OFFSET ? ';
    push(@$values, $prep->{offset});
  };

  return $sql;
};


# Questionmark string
sub _q ($) {
  join(',', split('', '?' x scalar(@{$_[0]})));
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
    $oro->transaction(sub {

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

  my ($rv, $sth) = $oro->('SELECT ? From Person', ['name'], 'cached');
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
The return value is identical to L<select>.
If no rows are found, the return value is C<undef>.

B<Note>: This method is experimental

=head2 C<transaction>

  $oro->transaction(
    sub {
      foreach (1..100) {
        $oro->insert(Person => { name => 'Peter'.$_ }) or return -1;
      };
      $oro->delete(Person => { id => 400 });

      $oro->transaction(
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

L<DBI>,
L<DBD::SQLite>,
L<File::Path>,
L<File::Basename>.


=head1 AVAILABILITY

  https://github.com/Akron/Sojolicious


=head1 COPYRIGHT AND LICENSE

Copyright (C) 2011, Nils Diewald.

This program is free software, you can redistribute it
and/or modify it under the same terms as Perl.

=cut
