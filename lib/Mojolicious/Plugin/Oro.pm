package Mojolicious::Plugin::Oro;
use Mojo::Base 'Mojolicious::Plugin';
use Carp qw/carp croak/;

# Database driver
use Sojolicious::Oro;

# Register Plugin
sub register {
  my ($plugin, $mojo, $param) = @_;

  # Hash of database handles
  my $databases = $mojo->attr('oro_handles');

  unless ($databases) {
    $databases = {};
    $mojo->attr(
      oro_handles => sub {
	return $databases;
      }
    );
  };

  # Init databases
  foreach my $name (keys %$param) {
    my $db = $param->{$name};

    # Already exists
    next if exists $databases->{$name};

    # No file name given
    croak "No file given for database '$name'" unless $db->{file};

    # Get Database handle
    my $oro = Sojolicious::Oro->new( $db->{file} );

    # No succesful creation
    croak "Unable to create database handle '$name'" unless $oro;

    # Initialize database
    if (exists $db->{init} &&
	  $oro->created &&
	    ref($db->{init})) {

      # Start transaction
      $oro->txn(
	sub {
	  # Start init callback
	  return $db->{init}->( $oro );
	});
    };

    # Store database handle
    $databases->{$name} = $oro;
  };

  # Add helper
  $mojo->helper(
    oro => sub {
      my ($c, $name, $table) = @_;
      my $oro = $databases->{$name};

      # Database unknown
      carp "Unknown database '$name'" unless $oro;

      # Return database handle
      return $oro unless $table;

      # Return table handle
      return $oro->table($table);
   });
};

1;

__END__

=head1 NAME

Mojolicious::Plugin::Oro - Oro Database driver Plugin

=head1 SYNOPSIS

  $app->plugin('Oro' => {
    Books => {
      file => 'Database/Books.sqlite'
    }}
  );

  $c->oro('Books')->insert(Content => { title => 'IT'});
  print $c->oro(Books => 'Content')->count;

=head1 DESCRIPTION

L<Mojolicious::Plugin::Oro> is a simple plugin to work with
L<Sojolicious::Oro>.

=head1 REGISTER

  # Mojolicious
  $app->plugin('Oro' => {
    Books => {
      file => 'Database/Books.sqlite',
      init => sub {
        my $oro = shift;
        $oro->do('CREATE TABLE Content (
                     id      INTEGER PRIMARY KEY,
                     title   TEXT,
                     content TEXT
                  )') or return -1;
      }
    }}
  );

  # Mojolicious::Lite
  plugin 'Oro' => {
    Books => {
      file => 'Database/Books.sqlite'
    }
  };

On creation, the plugin accepts a hash of database names
associated with hashrefs, giving the filename with the
parameter C<file> and an optional anonymous function with
the parameter C<init>.
The callback is executed on initialization if the database
is newly created. The first argument passed to the callback
is the associated C<Sojolicious::Oro> handle.

=head1 HELPERS

=head2 C<oro>

  # In Controllers:
  $c->oro('Books')->insert(Content => { title => 'IT'});
  print $c->oro(Books => 'Content')->count;

Returns an Oro database handle if registered.
Accepts the name of the registered database and optionally
a table name.

=head1 DEPENDENCIES

L<Mojolicious> (best with SSL support),
L<Sojolicious::Oro>.

=head1 AVAILABILITY

  https://github.com/Akron/Sojolicious

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2012, Nils Diewald.

This program is free software, you can redistribute it
and/or modify it under the same terms as Perl.

=cut
