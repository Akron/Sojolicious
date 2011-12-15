package Mojolicious::Plugin::PortableContacts;
use Mojo::Base 'Mojolicious::Plugin';

# Load Response and Entry objects
use Mojolicious::Plugin::PortableContacts::Response;
use Mojolicious::Plugin::PortableContacts::Entry;

has 'host';
has 'secure' => 0;

# Default count parameter
# Todo: itemsPerPage
has 'count' => 0; # unlimited

# Set condition regex
our (%CONDITIONS_RE, $poco_ns);
BEGIN {
  our %CONDITIONS_RE = (
    filterBy     => qr/./,
    filterOp     => qr/^(?:equals|contains|startswith|present)$/,
    filterValue  => qr/./,
    updatedSince => qr/./,
    sortBy       => qr/./,
    sortOrder    => qr/^(?:a|de)scending$/,
    startIndex   => qr/^\d+$/,
    count        => qr/^\d+$/,
    fields       => qr/^(?:[a-zA-Z,\s]+|\@all)$/
  );

  # Set PortableContacts namespace
  our $poco_ns = 'http://portablecontacts.net/spec/1.0';
};

# Todo:
# Updates via http://www.w3.org/TR/2011/WD-contacts-api-20110616/

# Register Plugin
sub register {
  my ($plugin, $mojo, $param) = @_;

  # Load Host-Meta if not already loaded.
  # This automatically loads the 'XRD' and 'Util-Endpoint' plugin.
  unless (exists $mojo->renderer->helpers->{'hostmeta'}) {
    $mojo->plugin('HostMeta', {'host' => $param->{'host'} });
  };

  # Set host
  if (exists $param->{host}) {
    $plugin->host( $param->{host} );
  } else {
# TODO: This is not supported anymore!
    $plugin->host( $mojo->hostmeta('host') || 'localhost' );
  };

  # Set secure
  $plugin->secure( $param->{secure} );

  # Add 'poco' shortcut
  $mojo->routes->add_shortcut(
    'poco' => sub {
      my ($route, $param) = @_;

      # Set endpoint
      $route->endpoint(
	'poco' => {
	  host   => $plugin->host,
	  scheme => $plugin->secure ? 'https' : 'http'
	});

      # Add Route to Hostmeta - exactly once
      $mojo->hook(
	'on_prepare_hostmeta' => sub {
	  my ($plugin, $c, $xrd_ref) = @_;

	  # The endpoint now may return the correct host

	  for ($xrd_ref->add_link($poco_ns =>
	      { href => $c->endpoint('poco') })) {
	    $_->comment('Portable Contacts');
	    $_->add('Title','Portable Contacts API Endpoint');
	  };

	}
      );


      # Todo: Check OAuth2 and fill $c->stash->{'poco_user_id'}

      # /@me/@all/
      my $me_all = $route->waypoint('/')->name('poco/@me/@all-1')->to(
	cb => sub {
	  $plugin->_multiple( shift );
	});
      $me_all->route('/@me/@all')->name('poco/@me/@all-2')->to;

      # /@me/@all/{id}
      $route->route('/@me/@all/:id')->name('poco/@me/@all/{id}')->to(
	cb => sub {
	  my $c = shift;
	  $c->stash('poco.user_id' => $c->stash('id'));
	  return $plugin->_single($c);
	});

      # /@me/@self
      $route->route('/@me/@self')->name('poco/@me/@self')->to(
	cb => sub {
	  my $c = shift;
	  $c->stash('poco.user_id' => $c->stash('poco.me_id'));
	  return $plugin->_single($c);
	});

      return;
    });

  # Add 'poco' helper
  $mojo->helper('poco'        => sub { $plugin->read( @_ );   } );
  $mojo->helper('create_poco' => sub { $plugin->_set('create' => @_ ); } );
  $mojo->helper('update_poco' => sub { $plugin->_set('update' => @_ ); } );
  $mojo->helper('delete_poco' => sub { $plugin->_set('delete' => @_ ); } );
  $mojo->helper('render_poco' => sub { $plugin->render( @_ ); } );
};


# Get PortableContacts
sub read {
  my $plugin = shift;
  my $c = shift;

  # Init response object
  my $response = { entry => (@_ > 1 ? [] : +{} ) };

  # Return empty response if no parameter was set
  return _new_response($response) unless defined $_[0];

  # Accept id or param hashref
  my $param = (@_ > 1) ? { @_ } : { id => $_[0] };

  # Run 'get_poco' hook
  $c->app->plugins->emit_hook('read_poco',
			      $plugin,
			      $c,
			      $param,
			      $response);

  return _new_response($response);
};


# Change PortableContacts Entry
sub _set {
  my $plugin  = shift;
  my $action  = lc( shift(@_) );
  my $c       = shift;

  # New Entry
  my $entry = Mojolicious::Plugin::PortableContacts::Entry->new(@_);

  return unless $entry;

  # Create new entry
  if ($action eq 'create') {
    delete $entry->{id};
  }

  # Unable to delete or update entry without id
  elsif (not exists $entry->{id}) {
    $c->app->log->debug("No ID given on PoCo $action.");
    return;
  };

  # Run 'x_poco' hook
  my $ok = 0;
  $c->app->plugins->emit_hook($action . '_poco',
			      $plugin,
			      $c,
			      $entry,
			      \$ok);

  # Everything went fine
  return $entry if $ok;

  # Something went wrong
  return;
};


# Return response for /@me/@self or /@me/@all/{id}
sub _single {
  my ($plugin, $c) = @_;

  my $id = $c->stash('poco.user_id');

  my $response = {entry => +{}};
  my $status   = 404;

  if ($id) {

    # Clone parameters with values
    my %param;
    foreach ($c->param) {
      $param{$_} = $c->param($_) if $c->param($_);
    };

    # Get results
    $response = $plugin->read(
      $c => (
	$plugin->_get_param(\%param),
	id => $id
      )
    );

    $status = 200 if $response->totalResults;
  };

  # Render poco
  return $plugin->render(
    $c => _new_response($response),
    status => $status
  );
};


# Return response for /@me/@all
sub _multiple {
  my ($plugin, $c) = @_;

  # Clone parameters with values
  my %param;
  foreach ($c->param) {
    $param{$_} = $c->param($_) if $c->param($_);
  };

  # Get results
  my $response = $plugin->read( $c =>
				  $plugin->_get_param(\%param));

  # Render poco
  return $plugin->render($c => $response);
};


# Check for valid parameters
sub _get_param {
  my $plugin = shift;
  my %param = %{ shift(@_) };

  my %new_param;
  foreach my $cond (keys %CONDITIONS_RE) {
    if (exists $param{$cond}) {

      # Valid
      if ($param{$cond} =~ $CONDITIONS_RE{$cond}) {
	$new_param{$cond} = $param{$cond};
      }

      # Not valid
      else {
	$plugin->app->log->debug(
	  'Not a valid PoCo parameter: '.
	    qq{"$cond": "$param{$cond}"});
      };
    };
  };

  # Set correct count parameter
  my $count = $plugin->count;
  if (exists $new_param{count}) {

    # There is a default count value
    if ($count) {

      # Count is valid
      if ($count > $new_param{count}) {
	$count =  delete $new_param{count};
      }

      # Count is invalid
      else {
	delete $new_param{count};
	delete $new_param{startIndex};
      };
    }

    # No count as default
    else {
      $count = delete $new_param{count};
    };
  };

  # set new count value
  $new_param{count} = $count if $count;

  # return new parameters
  return %new_param;
};


# Private function for response objects
sub _new_response {

  # Object is already response object
  if (ref($_[0]) eq
	'Mojolicious::Plugin::PortableContacts::Response') {
    return $_[0];
  }

  # Create new response object
  else {
    return Mojolicious::Plugin::PortableContacts::Response->new(@_);
  };
};

# respond to poco
sub render {
  my $plugin = shift;
  my $c = shift;
  my $response = shift;
  my %param = @_;

  # Return value RESTful
  return $c->respond_to(

    # Render as xml
    xml => sub {
      shift->render(
	'status' => $param{status} || 200,
	'format' => 'xml',
	'data'   => $response->to_xml
      )
    },

    # Render as JSON
    any => sub {
      shift->render(
	'status' => $param{status} || 200,
	'format' => 'json',
	'data'   => $response->to_json
      )
    }
  );
};

1;

__END__

=pod

=head1 NAME

Mojolicious::Plugin::PortableContacts

=head1 SYNOPSIS

  # Mojolicious
  $app->plugin('PortableContacts' => { count => 20});

  # Mojolicious::Lite
  plugin 'PortableContacts', count => 20;

  my $response = $c->poco( filterBy    => 'name.givenName',
                           filterOp    => 'startswith',
                           filterValue => 'Ak',
                           fields      => 'name,birthday');

  print $response->entry->[0]->to_xml;

  return $c->render_poco($response);

=head1 DESCRIPTION

L<Mojolicious::Plugin::PortableContacts> provides tools for
the PortableContacts API as described in L<http://portablecontacts.net/draft-spec.html>.

This plugin is database agnostic. Communication with a datastore
can be enabled via Hooks.

=head1 ATTRIBUTES

=head2 C<host>

  $pc->host('sojolicio.us');
  my $host = $pc->host;

The host for the PortableContacts Endpoint.

=head2 C<secure>

  $pc->secure(1);
  my $sec = $pc->secure;

Use C<http> or C<https>.

=head2 C<count>

  $pc->count(1);
  my $count = $pc->count;

Default and maximum number of items per page.
Defaults to 0, which means that there is no limit.

=head1 HELPERS

=head2 C<poco>

  # In Controller:
  my $response = $c->poco( filterBy    => 'name.givenName',
                           filterOp    => 'startswith',
                           filterValue => 'Ak',
                           fields      => 'name,birthday');

The helper C<poco> returns the result set of a PortableContacts
Query as a L<Mojolicious::Plugin::PortableContacts::Response> object.
The minimal set of possible parameters are described
L<http://portablecontacts.net/draft-spec.html>.
In addition to that, user ids (as in /@me/@all/{id}) should be
provided as C<me_id => {id}> and C<id => {id}>.

=head2 C<create_poco>

  my $entry = $c->create_poco( displayName => 'Homer',
                               name => {
                                 givenName => 'Homer',
                                 familyName => 'Simpson'
                               });
  print $entry->{id}; # 15

The helper C<create_poco> saves a new PortableContacts entry.
Returns the new PortableContacts entry.

=head2 C<update_poco>

  my $entry = $c->update_poco( displayName => 'Homer J.',
                               id => 15 );
  print $entry->{displayName},' ',$entry->{name}->{familyName};
  # Homer J. Simpson

The helper C<update_poco> updates an existing PortableContacts entry,
identified by the given C<id> parameter.
Returns the updated PortableContacts entry.
The exact behaviour (e.g., for plural values or deletion of partial data)
is undefined and depends on the storage implementation.

=head2 C<delete_poco>

  my $entry = $c->delete_poco( id => 15 );

The helper C<delete_poco> deletes an existing PortableContacts entry,
identified by the given C<id> parameter.
Returns an empty PortableContacts entry.

=head1 SHORTCUTS

=head2 C<poco>

  $r->route('/contacts')->poco;
  # PoCo Endpoint
  # Establishes the routes for
  #  /contacts/
  #  /contacts/@me/@self
  #  /contacts/@me/@all
  #  /contacts/@me/@all/{id}

L<Mojolicious::Plugin::PortableContacts> provides a route shortcut
for serving the PortableContacts API endpoint.

=head1 HOOKS

=over 2

=item C<get_poco>

This hook is run to retrieve the PortableContacts query result set
from a data store.
The hook passes the current plugin object, the current Controller object,
the query parameters as a hash reference and an empty
L<Mojolicious::Plugin::PortableContacts::Response> object, expected to
be filled with the requested result set.

=back

=head1 DEPENDENCIES

L<Mojolicious>,
L<Mojolicious::Plugin::HostMeta>.

=head1 AVAILABILITY

  https://github.com/Akron/Sojolicious

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2011, Nils Diewald.

This program is free software, you can redistribute it
and/or modify it under the same terms as Perl.

=cut
