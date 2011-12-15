package Sojolicious::Oro;
use Mojo::Base -base;

# Database connection
use DBI;
use DBD::SQLite;

# Find database file
use File::Path;
use File::Basename;

has ['dbh', 'file'];
has created => 0;

# Todo: allow more than 500 insertions at a time

# Constructor
sub new {
  my ($class, $file, $cb) = @_;

  my $self  = $class->SUPER::new;

  # Store filename
  $self->file($file);

  die 'No database defined' unless $file;

  # Create path for file - based on ORLite
  my $created = 0;
  unless (-f $file) {
    $created = 1;
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
  $self->dbh($dbh);

  # Store create information
  $self->created($created);

  # Release callback
  $cb->($self) if $cb && ref($cb) eq 'CODE';

  return $self;
};


# Insert values to database
sub insert {
  my $self  = shift;
  my $table = shift;

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
    my ($rv) = $self->_prepare_and_execute( $sql, \@values );

    return $rv;

  }

  # Multiple inserts
  elsif (ref($_[0]) eq 'ARRAY') {

    return unless $_[1];

    my @keys = @{ shift(@_) };

    my $sql   = 'INSERT INTO ' . $table . ' (' . join(', ', @keys) .') ';
    my $union = ' SELECT ' . _q(\@keys). ' ';

    if (@_ >= 500) {
      warn 'You are limited to 500 insertions at a time.';
      return;
    };

    # Add data unions
    $sql .= $union . ((' UNION ' . $union) x (scalar(@_) - 1));

    # Get database handle
    my $dbh = $self->dbh;

    # Prepare
    my $sth;
    eval {
      $sth = $dbh->prepare($sql);
    };

    # Check for errors
    if ($@) {
      warn $@;
      return;
    };

    # Execute
    eval {
      $sth->execute(map( @$_,  @_ ));
    };

    # Check for errors
    if ($@) {
      warn $@;
      return 0;
    };

    # Everything went fine
    return 1;
  };

  # Unknown query
  return;
};


# Update existing values in the database
sub update {
  my $self  = shift;
  my $table = shift;

  # No parameters
  return unless $_[0];

  my ($pairs, $values) = _get_pairs( shift(@_) );

  # Nothing to update
  return unless @$pairs;

  my $sql = 'UPDATE ' . $table .
            ' SET ' . join(', ', @$pairs);

  if ($_[0]) {
    my ($cond_pairs, $cond_values) = _get_pairs(shift(@_));

    # Append condition
    if (@$cond_pairs) {
      $sql .= ' WHERE ' . join(' AND ', @$cond_pairs);

      # Append values
      push(@$values, @$cond_values);
    };
  };

  # Prepare and execute
  my ($rv) = $self->_prepare_and_execute($sql, $values);

  # Return value
  return (!$rv || $rv eq '0E0') ? 0 : $rv;
};


# Select from table
sub select {
  my $self  = shift;
  my $table = shift;

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
    my ($pairs, $values) = _get_pairs( shift(@_) );

    $sql .= ' WHERE ' . join(' AND ', @$pairs);
    push(@values, @$values);
  };

  # Prepare and execute
  my ($rv, $sth) = $self->_prepare_and_execute($sql, \@values);

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
  my $table = shift;

  # Fields to select
  my $fields = '*';
  if ($_[0] && ref($_[0]) && ref($_[0]) eq 'ARRAY') {
    $fields = _fields( shift(@_) );
  };

  # No parameters
  return unless $_[0];

  my ($pairs, $values) = _get_pairs( shift(@_) );

  # Build sql
  my $sql = 'SELECT ' . $fields . ' FROM ' . $table .
            ' WHERE ' . join(' AND ', @$pairs);

  # Prepare and execute
  my ($rv, $sth) = $self->_prepare_and_execute($sql, $values);

  # Retrieve
  return $sth ? $sth->fetchrow_hashref : {};
};


# Delete entry
sub delete {
  my $self  = shift;
  my $table = shift;

  # No parameters
  return unless $_[0];

  my ($pairs, $values) = _get_pairs( shift(@_) );

  # Build sql
  my $sql = 'DELETE FROM ' . $table .
            ' WHERE ' . join(' AND ', @$pairs);

  # Prepare and execute
  my ($rv, $sth) = $self->_prepare_and_execute($sql, $values);

  return (!$rv || $rv eq '0E0') ? 0 : $rv;
};


# Update or insert a value
sub update_or_insert {
  my $self  = shift;
  my $table = shift;

  my %param = %{ shift( @_ ) };
  my %cond  = ();

  if ($_[0]) {
    %cond  = %{ shift( @_ ) };

    # Update
    # Todo: return 0 if error!
    my $up = $self->update($table, \%param, \%cond);
    return $up if $up && $up > 0;
  };

  # Delete all element conditions
  delete $cond{$_} foreach grep( ref( $cond{$_} ), keys %cond);

  # Insert
  return $self->insert($table, { %param, %cond });
};

# Last insert id
sub last_insert_id {
  shift->dbh->sqlite_last_insert_rowid;
};

# Wrapper for dbi do
sub do {
  shift->dbh->do( @_ );
};


# get pairs and values
sub _get_pairs {
  my (@pairs, @values);
  while (my ($key, $value) = each %{$_[0]}) {
    next unless $key =~ /^[_0-9a-zA-Z]+$/;

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
  return (\@pairs, \@values);
};


# Get filds
sub _fields {
  join(', ', grep(/^[\._0-9a-zA-Z]+$/, @{ $_[0] }));
};

sub _prepare_and_execute {
  my ($self, $sql, $values) = @_;

  # Prepare
  my $sth;
  eval {
    $sth = $self->dbh->prepare( $sql );
  };

  # Check for errors
  if ($@) {
    warn $@;
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
    warn $@;
    return;
  };

  # Return values
  return ($rv, $sth);
};

# questionmark string
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
            id   INTEGER PRIMARY KEY,
            name TEXT NOT NULL,
     )'
    );
  };
  $oro->insert(Person => { name => 'Peter'});
  my $person = $oro->load(Person => { id => 4 });

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
    # brand new
  };

If the database was created on construction of the handle,
this attribute is true. Otherwise it's false.

=head1 METHODS

=head2 C<new>

  $oro = Sojolicious::Oro->new('test.sqlite');
  $oro = Sojolicious::Oro->new('test.sqlite' => sub {
    shift->do(
      'CREATE TABLE Person (
         id   INTEGER PRIMARY KEY,
         name TEXT NOT NULL,
      )');
  })

Creates a new sqlite database accessor object on the
given filename. If the database does not already exist,
it is created.
Accepts an optional callback that is only released, if
the database is newly created.

=head2 C<insert>

  $oro->insert(Person => { id => 4,
                           name => 'Peter' });
  $oro->insert(Person => ['id', 'name'] =>
                         [ 4, 'Peter'], [5, 'Sabine']);

Inserts a new row to a given table for single insertions.
Expects the table name and a hash ref of values to insert.

For multiple insertions in, it expects the table name
to insert, an arrayref of the column names and at maximum
500 array references of values to insert.

=head2 C<update>

  my $rows = $oro->update(Person => { name => 'Daniel' },
                                    { id   => 4 } );

Updates values of an existing row of a given table.
Expects the table name to update, a hash ref of values to update,
and optionally a hash ref with conditions, the rows have to fulfill.
In case of scalar values, identity is tested. In case of array refs,
it is tested, if the field is an element of the set.
Returns the number of rows affected.

=head2 C<update_or_insert>

  $oro->update_or_insert(Person =>  { name => 'Daniel' },
                                    { id   => 4 });

Updates values of an existing row of a given table,
otherways inserts them.
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
  my $users = $oro->select(Person => [qw/id name/]);
  my $users = $oro->select(Person => { name => 'Daniel' });
  my $users = $oro->select(Person => ['id'] => { name => 'Daniel' });
  my $users = $oro->select(Person => ['id'] => { id => [1,2,4] });
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
of fields, optionally a hash ref with conditions, the rows have to fulfill,
and optionally a callback, which is released after each row.
If the callback returns -1, the data fetching is aborted.
In case of scalar values, identity is tested in the condition hash ref.
In case of array refs, it is tested, if the field is an element of the set.

=head2 C<load>

  my $user = $oro->load(Person, { id => 4 });
  my $user = $oro->load(Person, ['name'], { id => 4 });

Returns a single hash ref of a given table,
that meets a given condition.
Expects the table name of selection, an optional array ref of fields
to return and a hash ref with conditions,
the rows have to fulfill. Normally this includes the primary key.
In case of scalar values, identity is tested. In case of array refs,
it is tested, if the field is an element of the set.

=head2 C<delete>

  my $rows = $oro->delete(Person => { id => 4 });

Deletes rows of a given table, that meet a given condition.
Expects the table name of selection and a hash ref with conditions,
the rows have to fulfill.
In case of scalar values, identity is tested. In case of array refs,
it is tested, if the field is an element of the set.
Returns the number of rows that were deleted.

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

L<Mojolicious>,
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
