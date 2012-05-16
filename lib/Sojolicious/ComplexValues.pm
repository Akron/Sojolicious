package Sojolicious::ComplexValues;
use strict;
use warnings;

our $VERSION = '0.01';

use Carp qw/carp croak/;

# Todo: Change update method to use id first if given.
# Todo: Change delete method to be also a wrapper
#       of read - deletion of all '---' res_ids.
# Todo: Create separated tutorial document.
# Todo: Introduce replace operation.
# Todo: Maybe a 'distinct' parameter
# Todo: Create an ->error string object
#       and return an error response for all actions
# Todo: Use carp and croak
# Todo: Check for possible views
# Todo: Maybe use UNIQUE keyword

# Todo:
# - Use CHI caching
# - Simple Caching of users

BEGIN {
  # Load RFC3339 module
  foreach (qw/Mojolicious::Plugin::Date::RFC3339
	      DateTime::Format::RFC3339/) {
    if (eval "require $_; 1;") {
      next if index($@, "Can't locate") == 0;
      ($Sojolicious::ComplexValues::RFC) = ($_ =~ /^([^:]+):/);
      last;
    };
  };

  # Unable to load
  croak 'Unable to load RFC3339 module'
    unless $Sojolicious::ComplexValues::RFC;
};

# Load Oro module
use Sojolicious::Oro;

# Load CRUD methods
use Sojolicious::ComplexValues::Create;
use Sojolicious::ComplexValues::Read;
use Sojolicious::ComplexValues::Update;
use Sojolicious::ComplexValues::Delete;


my $NAME_RE = qr{^[_a-zA-Z][_a-zA-Z0-9]*$};


# Constructor
sub new {
  my $class = shift;
  my $self = bless { @_ }, $class;

  # Set default items per page
  unless (defined $self->{items_per_page}) {
    $self->{items_per_page} = 10;
  };

  # Temporary
  if ($self->{oro} && $self->{oro}->driver ne 'SQLite') {
    carp __PACKAGE__ . ' ' . $VERSION . ' supports SQLite only';
    return;
  };

  unless ($self->{name} &&
	  $self->{name} =~ $NAME_RE) {
    carp 'You need to define a valid table name';
    return;
  };

  # Return object
  $self;
};


# Initialize database
sub init_db {
  my $self = shift;

  my $oro  = $self->{oro};
  my $name = $self->{name};
  my $pref = lc($name);

  # Begin transaction
  return $oro->txn(
    sub {

      # ComplexValues Table
      $oro->do(
	'CREATE TABLE ' . $name . ' (
           id        INTEGER PRIMARY KEY,
           res_id    INTEGER,
           obj_id    INTEGER,
           pri_key   VARCHAR(255),
           sec_key   VARCHAR(255),
           val       TEXT
        )'
      ) or return -1;

      $oro->do('ANALYZE ' . $name) or return -1;

      # ComplexValues Indices
      my $counter = 1;
      foreach ('res_id, pri_key, sec_key, val',
	       'val, sec_key, pri_key, res_id',
	       'res_id, pri_key') {
	$oro->do(
	  'CREATE INDEX IF NOT EXISTS ' .
	  $pref . '_complex_' . $counter++ . '_i ' .
	  'ON ' . $name . ' (' . $_  . ')'
	) or return -1;
      };

      foreach (qw/res_id val/) {
	$oro->do(
	  'CREATE INDEX IF NOT EXISTS ' .
          $pref . '_' . $_ . '_i ' .
	  'ON ' . $name . ' (' . $_ . ')'
	) or return -1;
      };

      # Create Updated table with fk constraint
      $oro->do(
	'CREATE TABLE ' . $name . '_UPDATED (
           res_id    INTEGER UNIQUE,
           updated   INTEGER,
           FOREIGN KEY (res_id) REFERENCES ' . $name . ' (res_id)
        )'
      ) or return -1;

      # Create Updated index
      foreach (qw/updated res_id/) {
	$oro->do(
	  'CREATE INDEX IF NOT EXISTS ' .
	  $pref . '_updated_' . $_ . '_i ' .
	  'ON ' . $name . '_UPDATED (' . $_ . ')'
	) or return -1;
      };

      # Create trigger update
      $oro->do(
	'CREATE TRIGGER
           ' . $name . '_update_updated
         AFTER UPDATE OF updated
           ON ' . $name . '_UPDATED
         BEGIN
           UPDATE ' . $name . ' SET
             val = new.updated
           WHERE
             res_id  = new.res_id AND
             pri_key = "updated";
         END') or return -1;

    });

  return $self;
};


# Oro Attribute
sub oro {
  my $self = shift;
  return $self->{oro} unless @_;
  if (index(ref($_[0]), 'Sojolicious::Oro') == 0) {
    $self->{oro} = shift;
    return 1;
  };
  return;
};


# Name Attribute
sub name {
  my $self = shift;
  return $self->{name} unless @_;
  if ($_[0] =~ $NAME_RE) {
    $self->{name} = shift;
    return 1;
  };
  carp 'You need to define a valid table name';
  return;
};


# Items per Page Attribute
sub items_per_page {
  my $self = shift;
  return $self->{items_per_page} unless @_;
  if ($_[0] =~ /^[0-9]+$/ && $_[0]) {
    $self->{items_per_page} = shift;
    return 1;
  };
  return;
};


1;


__END__

=pod

=head1 NAME

Sojolicious::ComplexValues - Database accessor for complex values

=head1 SYNOPSIS

  use Sojolicious::Oro;
  use Sojolicious::ComplexValues;

  my $cv = Sojolicious::ComplexValues->new(
    oro  => Sojolicious::Oro->new('file.sqlite'),
    name => 'MyComplexTable'
  );

  $cv->create({
    displayName => 'Homer',
    name => {
      givenName  => 'Homer',
      familyName => 'Simpson'
    },
    gender  => 'male',
    tags => ['nuclear power plant', 'father'],
    urls => [{
      value => 'http://www.thesimpsons.com/',
      type  => 'work'
    },{
      value => 'http://www.snpp.com/',
      type  => 'home'
    }]
  });

  my $response = $cv->read({
    filterBy    => 'name.givenName',
    filterOp    => 'startswith',
    filterValue => 'H',
    fields      => [qw/name displayName gender/],
    sortBy      => 'displayName',
    startIndex  => 2,
    count       => 4
  });

  print $response->{entry}->[0]->{displayName};

  $cv->update({
    id => 3,
    name => {
      middleName => 'J.'
    }
  });

  $cv->delete(1);

=head1 DESCRIPTION

L<Sojolicious::ComplexValues> allows for storing and retrieving
values with limited complexity in SQL databases (semi-schemaless).
It supports the query language of the
L<http://portablecontacts.net/draft-spec.html#query-params|PortableContacts>
specification.

=head1 ATTRIBUTES

=head2 C<oro>

  my $oro = $cv->oro;
  $cv->oro(Sojolicious::Oro->new('test.sqlite'));

The L<Sojolicious::Oro> accessor handle.


=head2 C<name>

  my $name = $cv->name;
  $cv->name('Resource');

The table name of the complex value resource.


=head2 C<items_per_page>

  print $cv->items_per_page;
  $cv->items_per_page(25);

The default number of items per page in the response.
Defaults to 10.


=head1 METHODS

=head2 C<new>

  my $oro = Sojolicious::Oro->new('file.sqlite');
  my $cv = Sojolicious::ComplexValues->new(
    oro  => $oro,
    name => 'PoCo',
    items_per_page => 25
  );

Creates a new complex value database acceptor.
Accepts a hash reference containing a handle to a
L<Sojolicious::Oro> instance and the name of the table.
In addition it allows for setting the value for items
shown per page on read (if not specified on retrieval).
The default value is 10.


=head2 C<create>

  my $obj_id = $cv->create({
    displayName => 'Homer',
    name => {
      givenName  => 'Homer',
      familyName => 'Simpson'
    },
    gender  => 'male',
    tags => ['nuclear power plant', 'father'],
    urls => [{
      value => 'http://www.thesimpsons.com/',
      type  => 'work'
    },
    {
      value => 'http://www.snpp.com/',
      type  => 'home'
    }]
  });

Stores a new complex item to the database and returns the object's
id on success. Otherwise returns C<undef>.
The complexity is not arbitrary - only the following degrees of
complexity are valid:

  # Simple values
  displayName => 'Homer'

  # Complex values
  name => {
    givenName  => 'Homer',
    familyName => 'Simpson'
  }

  # Plural simple values
  tags => ['nuclear power plant', 'father']

  # Plural complex values
  urls => [{
    value => 'http://www.thesimpsons.com/',
    type  => 'work'
  },
  {
    value => 'http://www.snpp.com/',
    type  => 'home'
  }]

A simple value 'updated' is automatically set to the current time
as a Unix timestamp.


=head2 C<read>

  my $response = $cv->read({
    filterBy    => 'name.givenName',
    filterOp    => 'startswith',
    filterValue => 'H',
    fields      => ['name','displayName','gender'],
    sortBy      => ['displayName'],
    startIndex  => 2,
    count       => 4
  });

  my $response = { error => 'no' };
  $cv->read({ id => 4 }, $response);

Retrieval of entries is rather complex. The supported query language is defined
in L<http://portablecontacts.net/draft-spec.html#query-params|PortableContacts>
(see L<below|Filtering>).
Expects a hash reference for querying and optional a second hash
with a predefined response hash reference.


=head3 ID Requests

=over 2

=item C<id>

In addition to the PortableContacts specification, it is also possible
to retrieve data sets by explicitely giving an C<id> value.

  my $response = $cv->read({
    id     => 1,
    fields => [qw/name urls/]
  });

When giving a numeric C<id> value, a single entry will be returned.
In case of an array reference or a comma separated list of ids,
multiple entries are returned.
When retrieving entries by ids, filtering is not enabled.

The response for a single entry has the following structure:

  {
    entry => {
      name => 'Homer',
      id =>   1,
      urls => [{
        value => 'http://www.thesimpsons.com/',
        type  => 'work'
      },
      {
        value => 'http://www.snpp.com/',
        type  => 'home'
      }]
    },
    startIndex   => 0,
    totalResults => 1
  }

The response for multiple entries has the following structure:

  {
    entry => [{
      name => 'Homer',
      id   => 1,
      urls => [{
        value => 'http://www.thesimpsons.com/',
        type  => 'work'
      },
      {
        value => 'http://www.snpp.com/',
        type  => 'home'
      }]
    },
    {
      name => 'Lisa',
      id   => 2
    }],
    startIndex   => 0,
    totalResults => 2
  }

=item C<id => '-'>, C<id => '---'>

Beside entries it is also possible to request ids only.

  $cv->read({
    id          => '-',
    filterBy    => 'name.givenName',
    filterOp    => 'startswith',
    filterValue => 'H',
  });

With the special parameter value C<'-'> one id matching the above
statement is returned. The response has the following structure:

  {
    id           => 1,
    startIndex   => 0,
    totalResults => 1
  }

With the parameter value C<'---'> all ids matching a statement
are returned. The response has the following structure:

  {
    id           => [1,2],
    startIndex   => 0,
    totalResults => 2
  }

=back


=head3 Filtering

=over 2

=item C<filterBy>

Field name to filter by. To filter by complex values both keys have to be given
with a defined '.' character, for example 'name.givenName'.

=item C<filterOp>

Defines the relation of the field and the given C<filterValue>.
Defined values are C<equals> for identical strings,
C<contains> for matching substrings and C<startswith> for matching prefixes.
C<present> checks for the existence of the field and does not need
a C<filterValue>.

=item C<filterValue>

Defines the string to compare the field given by C<filterBy> and the
relation given by C<filterOp>.

=item C<updatedSince>

Defines a Unix timestamp or a string according to
L<RFC3339|http://tools.ietf.org/html/rfc3339>
to only return items updated after this point in time.

=back


=head3 Sorting

=over 2

=item C<sortBy>

Defines the field name to sort the result by.
B<Note:> In difference to the specification, all plural values are treated
like complex values, there is currently no support for the 'primary' field.

=item C<sortOrder>

Defines the order of sorting.
Allowed values are C<ascending> and C<descending>.

=back


=head3 Pagination

=over 2

=item C<startIndex>

Defines the offset of the array of entries. The default value is 0.

=item C<count>

Defines the number of items per page. The default value is 10.
This default value can be overwritten in the constructor.

=back


=head3 Presentation

=over 2

=item C<fields>

Defines the fields to be returned, if only a subset is wanted.
Accepts a comma separated list as a string value or an array of
fields. Fields can only be major values.
The special value '@all' returns all fields.
The C<id> field is always returned.
The default value is '@all'.

=back

=head2 C<update>

  $cv->update({
    id => 4,
    gender => 'undisclosed',
    name => {
      middleName => 'J.'
    },
    tags => ['-father','+worker'],
    urls => [{
      'type'     => 'work',
      '+value'   => 'http://www.thesimpsons.com/index.html',
      'value'    => 'http://www.thesimpsons.com/',
      '-comment' => undef
      }]
  });

Updates an entry based on the C<id> parameter.

B<Note:> Updating a value with an inappropriate method can lead
to inconsistent data. In most cases, the updated values won't
be reachable by using this API. This method is experimental and
may change without warning.

To update the different forms of an entry, different methods are
needed:

  $cv->update({
    # Necessary identifier
    id => 4,

    # Update simple values
    gender => 'undisclosed',

    # Delete values (simple, complex, plural)
    urls => undef,

    # Update complex values
    name => {
      familyName => undef,
      middleName => 'J.'
    },

    # Update plural simple values
    tags => ['-father','+worker'],

    # Update existing plural complex value
    urls => [
      # Create plural complex value
      {
        '+value' => 'http://sojolicio.us/homer',
        '+type'  => 'profile'
      },
      # Delete
      {
        '-value' => 'http://www.snpp.com/',
      },
      # Update
      {
        'type'   => 'work',
        '+value' => 'http://www.thesimpsons.com/index.html',
        'value'  => 'http://www.thesimpsons.com/',
        '-comment' => undef
      }
    ]
  });

Simple and complex values will be overwritten or added,
if the value does not exist. If the key is given but the value
is set to C<undef>, the value will be deleted.

Plural simple values in an array need a prefix with C<+> meaning
the value should be added and C<-> meaning, the value should be deleted.

Plural complex values need prefixes to their keys to be updated.
If all keys have a C<+> prefix, the complex value will be created.
If all keys have a C<-> prefix, all complex values matching the given
parameters will be deleted.
If some keys have a C<+> prefix and some have a C<-> prefix or some
have no prefix at all, all complex values matching the C<-> prefix
parameters and the non-prefixed parameters will be updated,
with all keys having a C<+> prefix being added or
overwritten and all keys having a C<-> prefix being deleted.
If parameters with a C<-> prefix shall not be used as a condition
for matching plural complex values, the value of the parameter
can be set to C<undef>.
When keys are inserted or updated as well as deleted,
deletion always wins.

  $cv->update({
    id => 1,
    urls => [
      # Delete all entries with rel='work'
      {
        '-rel' => 'work'
      },
      # Delete all rel-parameters in all entries with rel='work'
      {
        '-rel' => undef,
        'rel'  => 'work'
      }
      # Update 'rel' in all entries with href='http://sojolicio.us/'
      {
        '+rel' => 'home',
        'href' => 'http://sojolicio.us/'
      },
      # Update 'href' in all entries with rel='home'
      {
        'rel' => 'home',
        '+href' => 'http://sojolicio.us/akron'
      }
      # Update 'href' in all entries with rel='home' and delete 'rel'
      {
        '-rel' => 'home',
        '+href' => 'http://sojolicio.us/akron'
      }
    ]
  });

As with simple values, all plural values can be completely deleted by
setting the primary level key to C<undef>.

B<note>: As for now due to implementation details, the less parameters
you need to describe which plural complex value you want to update,
the better the performance is.

=head2 C<delete>

  $cv->delete(4);
  $cv->delete([3,5,6]);

Deletes one or multiple complex values from the database
based on their C<id>s.

=head2 C<init_db>

Initialize the database table. In most cases, this should be done when
the database file was just created, for example like this:

  my $oro = Sojolicious::Oro->new('file.sqlite');

  my $cv = Sojolicious::ComplexValues->new(
    oro  => $oro,
    name => 'MyComplexTable' # Table name
  );

  if ($oro->created) {
    $cv->init_db or die 'Unable to create database!';
  };

Returns the complex value object on success, otherwise C<undef>.

=head1 DEPENDENCIES

L<Sojolicious::Oro>,
L<DateTime::Format::RFC3339> or
L<Mojolicious::Plugin::Date::RFC3339>.

=head1 AVAILABILITY

  https://github.com/Akron/Sojolicious

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2011-2012, Nils Diewald.

This program is free software, you can redistribute it
and/or modify it under the same terms as Perl.

=cut
