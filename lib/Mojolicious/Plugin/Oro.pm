package Mojolicious::Plugin::Oro;
use Mojo::Base 'Mojolicious::Plugin';
use Carp qw/carp croak/;

# Database driver
use DBIx::Oro;

# Register Plugin
sub register {
  my ($plugin, $mojo, $param) = @_;

  # Load parameter from Config file
  if (my $config_param = $mojo->config('Oro')) {
    $param = { %$config_param, %$param };
  };

  # Hash of database handles
  my $databases;

  # No databases attached
  unless ($mojo->can('oro_handles')) {
    $databases = {};
    $mojo->attr(
      oro_handles => sub {
	return $databases;
      });
  }
  else {
    $databases = $mojo->oro_handles;
  };

  # Add oro_init command
  push @{$mojo->commands->namespaces}, __PACKAGE__;

  # Init databases
  Mojo::IOLoop->timer(
    0 => sub {

      foreach my $name (keys %$param) {
	my $db = $param->{$name};

	# Already exists
	next if exists $databases->{$name};

	# Get Database handle
	my $oro = DBIx::Oro->new(
	  %$db,
	  on_connect => sub {
	    my $oro = shift;
	    $mojo->log->info( 'Connect ' . $name . ' from ' . $$ );

	    # Emit on_oro_connect hook
	    $mojo->plugins->emit_hook(
	      'on_' . ($name ne 'default' ? $name . '_' : '') . 'oro_connect' =>
		$oro
	      );
          }
	);

	if ($oro->created) {

	  # Emit on_oro_init hook
	  $mojo->plugins->emit_hook(
	    'on_' . ($name ne 'default' ? $name . '_' : '') . 'oro_init' =>
	      $oro
	    );

	  # Initialization log message
	  $mojo->log->debug(qq{Initialize Oro-DB "$name"});
	};

	# No succesful creation
	croak "Unable to create database handle '$name'" unless $oro;

	# Store database handle
	$databases->{$name} = $oro;
      };
    }
  );

  # Add helper
  $mojo->helper(
    oro => sub {
      my ($c, $name, $table) = @_;
      $name //= 'default';
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

=pod

=head1 NAME

Mojolicious::Plugin::Oro - Oro Database driver Plugin

=head1 SYNOPSIS

  $app->plugin('Oro' => {
    Books => {
      file => 'Database/Books.sqlite'
    }
  );

  # Or in your config file
  {
    Oro => {
      default => { file => ':memory:' }
    }
  }

  $c->oro('Books')->insert(Content => { title => 'Misery' });
  print $c->oro(Books => 'Content')->count;

=head1 DESCRIPTION

L<Mojolicious::Plugin::Oro> is a simple plugin to work with
L<DBIx::Oro>.

=head1 HELPERS

=head2 C<oro>

  # In Controllers:
  $c->oro('Books')->insert(Content => { title => 'Misery' });
  print $c->oro(Books => 'Content')->count;

Returns an Oro database handle if registered.
Accepts the name of the registered database and optionally
a table name.
If no database handle name is given, a database handle name
C<default> is assumed.


=head1 METHODS

=head2 C<register>

  # Mojolicious
  $app->plugin('Oro' => {
    Books => {
      file => 'Database/Books.sqlite',
      init => sub {
        my $oro = shift;
        $oro->txn(sub{
          $oro->do('CREATE TABLE Content (
                       id      INTEGER PRIMARY KEY,
                       title   TEXT,
                       content TEXT
                    )') or return -1;
          }) or return;
      }
    }}
  );

  # Mojolicious::Lite
  plugin 'Oro' => {
    Books => { file => 'Database/Books.sqlite' }
  };

Called when registering the plugin.
On creation, the plugin accepts a hash of database names
associated with a L<DBIx::Oro> object.
All parameters can be set either on registration or
as part of the configuration file with the key C<Oro>.

=head1 HOOKS

=head2 C<on_DBNAME_oro_init>

  $app->plugin(Oro => {
    Books => {
      file => 'Database/Books.sqlite';
    }
  });

  $app->hook(
    on_Books_oro_init => sub {
      my $oro = shift;
      $oro->init_db;
    });

This hook is run when an oro database of the given name
is initialized. In case of the default database,
the handle of the hook is C<on_oro_init>.
This hook will be automatically released in case an
SQLite database was created.


=head2 C<on_DBNAME_oro_connect>

  $app->plugin(Oro => {
    Books => {
      file => 'Database/Books.sqlite';
    }
  });

  $app->hook(
    on_Books_oro_connect => sub {
      my $oro = shift;
      $app->log->debug('Database ' . $oro->file . ' is connected!');
    });


This hook is run when an oro database of the given name
is connected. In case of the default database,
the handle of the hook is C<on_oro_connect>.


=head1 COMMANDS

=head2 C<oro_init>

  perl app.pl oro_init

As the hook C<on_DBNAME_oro_init> is only automatically released
in case of newly created SQLite instances, the hook can be forced
by manually initializing the databases using the
L<Mojolicious::Plugin::Oro::oro_init> command.


=head1 DEPENDENCIES

L<Mojolicious>,
L<DBIx::Oro>.


=head1 AVAILABILITY

  https://github.com/Akron/Sojolicious


=head1 COPYRIGHT AND LICENSE

Copyright (C) 2012, Nils Diewald.

This program is free software, you can redistribute it
and/or modify it under the same terms as Perl.

=cut
