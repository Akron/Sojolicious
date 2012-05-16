package Sojolicious::Oro::SQLite;
use strict;
use warnings;

# Defaults to 500 for SQLITE_MAX_COMPOUND_SELECT
use constant MAX_COMP_SELECT => 500;

use base 'Sojolicious::Oro';
use feature qw/switch state/;
use Carp qw/carp/;

# Find and create database file
use File::Path;
use File::Basename;

# Todo: Make matching on separate columns easy

# Default arguments for snippet function
my @arguments = qw/start end ellipsis
		   column token/;
my @default = ('<b>', '</b>', '<b>...</b>', -1, -15);


# Constructor
sub new {
  my $class = shift;
  my %param = @_;

  # Bless object with hash
  my $self = bless \%param, $class;

  # Store filename
  my $file = $self->{file} = $param{file} // '';

  # Temporary or memory file
  if (!$file || $file eq ':memory:') {
    $self->{created} = 1;
  }

  # Create path for file - based on ORLite
  elsif (!-f $file) {
    $self->{created} = 1;

    my $dir = File::Basename::dirname($file);
    unless (-d $dir) {
      File::Path::mkpath( $dir, { verbose => 0 } );
    };
  };

  # Data source name
  $self->{dsn} = 'dbi:SQLite:dbname=' . $self->file;

  # Attach hash
  $self->{attached} = {};

  # Return object
  $self;
};


# Connect to database
sub _connect {
  my $self = shift;
  my $dbh = $self->SUPER::_connect( sqlite_unicode => 1 );

  # Set busy timeout
  $dbh->sqlite_busy_timeout( $self->{busy_timeout} || 300 );

  # Reattach possibly attached databases
  while (my ($db_name, $file) = each %{$self->{attached}}) {
    $self->prep_and_exec("ATTACH '$file' AS ?", [$db_name]);
  };

  # Return database handle
  $dbh;
};


# File of database
sub file { $_[0]->{file} // '' };


# Database driver
sub driver { 'SQLite' };


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


# Delete with SQLite feature
sub delete {
  my $self = shift;
  my $secure;

  # Check if -secure parameter is set
  if ($_[-1] && ref $_[-1] && ref $_[-1] eq 'HASH') {
    $secure = delete $_[-1]->{-secure} || 0;
  };

  # Delete
  unless ($secure) {
    return $self->SUPER::delete(@_);
  }

  # Delete securely
  else {

    # Security value
    my $sec_value;

    # Retrieve secure delete pragma
    my ($rv, $sth) = $self->prep_and_exec('PRAGMA secure_delete');
    $sec_value = $sth->fetchrow_array if $rv;
    $sth->finish;

    # Set secure_delete pragma
    $self->do('PRAGMA secure_delete = ON') unless $sec_value;

    # Delete
    $rv = $self->SUPER::delete(@_);

    # Reset secure_delete pragma
    $self->do('PRAGMA secure_delete = OFF') unless $sec_value;

    # Return value
    return $rv;
  };
};


# Insert values to database
sub insert {
  my $self  = shift;

  # Get table name
  my $table = $self->_table_name(\@_) or return;

  # No parameters
  return unless $_[0];

  # Properties
  my $prop = shift if ref $_[0] eq 'HASH' && ref $_[1];

  # Single insert
  if (ref $_[0] eq 'HASH') {

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
    my $sql = 'INSERT ';
    if ($prop) {
      given ($prop->{-on_conflict}) {
	when ('replace') { $sql .= 'OR REPLACE '};
	when ('ignore')  { $sql .= 'OR IGNORE '};
      };
    };

    $sql .= 'INTO ' . $table .
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



# Attach database
sub attach {
  my ($self, $db_name, $file) = @_;

  $file //= '';

  # Attach file, memory or temporary database
  if ($file eq ':memory:' || length($file) == 0 || -e $file) {
    my $rv = scalar $self->prep_and_exec("ATTACH '$file' AS ?", [$db_name]);
    $self->{attached}->{$db_name} = $file if $rv;
    return $rv;
  };

  return;
};


# Detach database
sub detach {
  my ($self, $db_name) = @_;
  return unless $db_name;
  delete $self->{attached}->{$db_name};
  return scalar $self->prep_and_exec('DETACH ?', [$db_name]);
};


# Wrapper for sqlite last_insert_row_id
sub last_insert_id {
  shift->dbh->sqlite_last_insert_rowid;
};


# Create matchinfo function
sub matchinfo {
  my $self   = shift;

  # Use no multibyte characters
  use bytes;

  # Format string
  my $format = lc(shift) if $_[0] && $_[0] =~ /^[pcnalsx]+$/i;

  # Return anonymous subroutine
  return sub {
    my $column;
    if (@_) {
      $column = shift || 'content';

      # Format string
      $format = lc(shift) if $_[0] && $_[0] =~ /^[pcnalsx]+$/i;
    };

    # Sort format for leading 'pc' if needed
    if ($format) {
      for ($format) {

	# Sort alphabetically
	$_ = join('', sort split('', $_));

	# Delete repeating characters
	s/(.)\1+/$1/g;

	# Prepend 'pc' if necessary
	if (/[xals]/) {
	  tr/pc//d;             # Delete 'pc'
	  $_ = 'pc' . $format;  # Prepend 'pc'
	};
      };
    }

    # No format given
    else {
      $format = 'pcx';
    };

    # Return anonymous subroutine
    return sub {
      return
	'matchinfo(' . $column . ', "' . $format . '")',
	  \&_matchinfo_return,
	    $format;
    };
  };
};


# Treat matchinfo return
sub _matchinfo_return {
  my ($blob, $format) = @_;

  # Get 32-bit blob chunks
  my @matchinfo = unpack('l' . (length($blob) * 4), $blob);

  # Parse format character
  my %match;
  foreach my $char (split '', $format) {
    given ($char) {

      # Characters: p, c, n
      when ([qw/p c n/]) {
	$match{$_} = shift @matchinfo;
      };

      # Characters: a, l, s
      when ([qw/a l s/]) {
	$match{$_} = [ splice(@matchinfo, 0, $match{c}) ];
      };

      # Characters: x
      when ('x') {
	my @match;
	for (1 .. ($match{p} * $match{c})) {
	  push(@match, [ splice(@matchinfo, 0, 3) ]);
	};

	$match{$_} = \@match;
      };

      # Unknown character
      default {
	shift @matchinfo;
      };
    };
  };
  return \%match;
};


# Create offsets function
sub offsets {
  my $self = shift;

  # Use no multibyte characters
  use bytes;

  # subroutine
  return sub {
    my $column = shift;
    'offsets(' . ($column || 'content') . ')',
      sub {
	my $blob = shift;
	my @offset;
	my @array = split(/\s/, $blob);
	while (@array) {
	  push(@offset, [ splice(@array, 0, 4) ]);
	};
	return \@offset;
      };
  };
};


# Create snippet function
sub snippet {
  my $self = shift;

  # Snippet parameters
  my @snippet;

  # Parameters are given
  if ($_[0]) {
    my %snippet = ();

    # Parameters are given as a hash
    if ($_[0] ~~ \@arguments) {
      %snippet = @_;
      foreach (keys %snippet) {
	carp "Unknown snippet parameter '$_'" unless $_ ~~ \@arguments;
      };
    }

    # Parameters are given as an array
    else {
      @snippet{@arguments} = @_;
    };

    # Trim parameter array and fill gaps with defaults
    my ($s, $i) = (0, 0);
    foreach (reverse @arguments) {
      $s = 1 if defined $snippet{$_};
      unshift(@snippet, $snippet{$_} // $default[$i]) if $s;
      $i++;
    };
  };

  # Return anonymous subroutine
  my $sub = 'sub {
  my $column = $_[0] ? shift : \'content\';
  my $str = "snippet(" . $column ';

  if ($snippet[0]) {
    $sub .= ' . ", ' . join(',', map { '\"' . $_ . '\"' } @snippet) . '"';
  };

  $sub .= " . \")\";\n};";

  return eval( $sub );
};


# Questionmark string
sub _q ($) {
  join(', ', split('', '?' x scalar( @{$_[0]} )));
};


1;


__END__

=pod

=head1 NAME

Sojolicious::Oro::SQLite - SQLite driver for Sojolicious::Oro


=head1 SYNOPSIS

  use Sojolicious::Oro;

  my $oro = Sojolicious::Oro->new('file.sqlite');

  $db->attach(blog => ':memory:');

  if ($oro->created) {
    $oro->do(
      'CREATE VIRTUAL TABLE Blog USING fts4(title, body)'
    );
  };

  $oro->insert(Blog => {
    title => 'My Birthday',
    body  => 'It was a wonderful party!'
  });

  my $snippet = $oro->snippet(
    start => '<strong>',
    end   => '</strong>',
    token => 10
  );

  my $birthday =
    $oro->load(Blog =>
      [ $oro->snippet => 'snippet'] =>
        { Blog => { match => 'birthday' } });

  print $birthday->{snippet};


=head1 DESCRIPTION

L<Sojolicious::Oro::SQLite> is an SQLite specific database
driver for L<Sojolicious::Oro> that provides further
functionalities.


=head1 ATTRIBUTES

L<Sojolicious::Oro::SQLite> inherits all attributes from
L<Sojolicious::Oro> and implements the following new ones
(with possibly overwriting inherited attributes).

=head2 C<file>

  my $file = $oro->file;
  $oro->file('myfile.sqlite');

The sqlite file of the database.
This can be a filename (with a path prefix),
':memory:' for memory databases or the empty
string for temporary files.

B<This attribute is EXPERIMENTAL and may change without warnings.>


=head1 METHODS

L<Sojolicious::Oro::SQLite> inherits all methods from
L<Sojolicious::Oro> and implements the following new ones
(with possibly overwriting inherited methods).


=head2 C<new>

  $oro = Sojolicious::Oro->new('test.sqlite');
  $oro = Sojolicious::Oro->new(':memory:');
  $oro = Sojolicious::Oro->new('');
  $oro = Sojolicious::Oro->new(
    file => 'test.sqlite',
    driver => 'SQLite',
    init => sub {
      shift->do(
        'CREATE TABLE Person (
            id    INTEGER PRIMARY KEY,
            name  TEXT NOT NULL,
            age   INTEGER
        )');
    }
  );

Creates a new SQLite database accessor object on the
given filename or in memory, if the filename is ':memory:'.
If the database file does not already exist, it is created.
If the file is the empty string, a temporary database
is created.

See L<Sojolicious::Oro::delete> for further information.


=head2 C<delete>

  $oro->delete(Person => { id => 4, -secure => 1});

Deletes rows of a given table, that meet a given condition.
See L<Sojolicious::Oro::delete> for further information.

=head3 Security

In addition to conditions, the deletion can have further parameters.

=over 2

=item C<-secure>

Forces a secure deletion by overwriting all data with '0'.

=back

B<The security parameter is EXPERIMENTAL and may change without warnings.>


=head2 C<attach>

  $oro->attach( another_db => 'users.sqlite');
  $oro->attach( another_db => ':memory:');
  $oro->attach( 'another_db' );
  $oro->load('another_db.user' => { id => 4 });

Attaches another database file to the connector. All tables of this
database can then be queried with the same connector.
Accepts the database handle name and a database file name.
If the file name is ':memory:' a new database is created in memory.
If no file name is given, a temporary database is created.
If the database file name does not exist, it returns undef.

The database handle can be used as a prefix for tables in queries.
The default prefix for tables of the parent database is C<main.>.

B<This method is EXPERIMENTAL and may change without warnings.>


=head2 C<detach>

  $oro->detach('another_db');

Detaches an attached database from the connection.

B<This method is EXPERIMENTAL and may change without warnings.>


=head1 TREATMENTS

Treatments can be used for the manipulation of C<select> and C<load>
queries. See L<Sojolicious::Oro::select>.

L<Sojolicious::Oro::SQLite> inherits all treatments from
L<Sojolicious::Oro> and implements the following new ones
(with possibly overwriting inherited treatments).


=head3 C<matchinfo>

  my $result = $oro->select(text =>
                 [[ $oro->matchinfo('nls') => 'matchinfo']] =>
                   { text => { match => 'default transaction' }};

  $result = [ { 'matchinfo' => {
  #                 'l' => [3,3],
  #                 'n' => 3,
  #                 'c' => 2,
  #                 'p' => 2,
  #                 's' => [2,0]
  #             }
  #           },{
  #             'matchinfo' => {
  #                 'l' => [4,3],
  #                 'n' => 3,
  #                 'c' => 2,
  #                 'p' => 2,
  #                 's' => [1,1]
  #           }}];

Creates a treatment for C<select> or C<load> that supports matchinfo information
for fts3/fts4 tables.
It accepts a format string containing the characters 'p', 'c', 'n', 'a', 'l', 's',
and 'x'. See the SQLite manual for further information on these characters.
The characters 'p' and 'c' will always be set.
Returns the column value as a hash reference of the associated values.


=head3 C<offsets>

  my $result = $oro->load(text =>
                  [[ $oro->offsets => 'offset' ]] =>
                    { text => { match => 'world' }});

  # $result = { 'offset' => [['0','0','6','5'],['1','0','24','5']] };


Creates a treatment for C<select> or C<load> that supports offset information
for fts3/fts4 tables.
It accepts no parameters and returns the column value as an array reference
containing multiple array references.


=head3 C<snippet>

  my $snippet = $oro->snippet(
    start    => '[',
    end      => ']',
    ellipsis => '',
    token    => 5,
    column   => 1
  );

  my $result = $oro->select(text =>
                  [[ $snippet => 'excerpt' ]] =>
                    { text => { match => 'cold' }});

Creates a treatment for C<select> or C<load> that supports snippets for
fts3/fts4 tables.
On creation it accepts the parameters C<start>, C<end>, C<ellipsis>,
C<token>, and C<column>. See the SQLite manual for a description on these.


=head1 SEE ALSO

The SQLite manual can be found at L<https://sqlite.org/>.
Especially interesting is the information regarding the fulltext search
extensions at L<https://sqlite.org/fts3.html>.


=head1 DEPENDENCIES

L<Carp>,
L<DBI>,
L<DBD::SQLite>,
L<File::Path>,
L<File::Basename>.


=head1 AVAILABILITY

  https://github.com/Akron/Sojolicious


=head1 COPYRIGHT AND LICENSE

Copyright (C) 2011-2012, Nils Diewald.

This program is free software, you can redistribute it
and/or modify it under the same terms as Perl.

=cut
