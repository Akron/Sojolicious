package Mojolicious::Plugin::PortableContacts;
use Mojo::Base 'Mojolicious::Plugin';

# Load Response and Entry objects
use Mojolicious::Plugin::PortableContacts::Response;
use Mojolicious::Plugin::PortableContacts::Entry;

has 'host';
has 'secure' => 0;

# Default count parameter
# TODO: itemsPerPage
# TODO: Make ->poco PortableContact Server as well as Client
# TODO: Check OAuth2 and fill $c->stash->{'poco.user_id'} -> poco.user_id
# TODO: Updates via http://www.w3.org/TR/2011/WD-contacts-api-20110616/

# Unlimited Items per page requested
has count => 0;

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

# Register Plugin
sub register {
  my ($plugin, $mojo, $param) = @_;

  # Load Host-Meta if not already loaded.
  # This automatically loads the 'XRD' and 'Util-Endpoint' plugin.
  unless (exists $mojo->renderer->helpers->{'hostmeta'}) {
    $mojo->plugin('HostMeta');
  };

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

	  # Endpoint link in XRD
	  my $link = $xrd_ref->add_link(
	    $poco_ns => {
	      href => $c->endpoint('poco')
	    });

	  # Add comment and title to link
	  for ($link) {
	    $_->comment('Portable Contacts');
	    $_->add('Title' => 'Portable Contacts API Endpoint');
	  };
	}
      );

      # Add route /@me/@all/
      my $me_all = $route->waypoint('/');
      for ($me_all) {
	$_->name('poco/@me/@all-1');

	# Implicit Route
	$_->to(
	  cb => sub {
	    $plugin->serve( shift );
	  });

	# Explicit Route
	$_->route('/@me/@all')
	  ->name('poco/@me/@all-2')->to;
      };

      # Add route /@me/@all/{id}
      my $me_id = $route->route('/@me/@all/:id');
      for ($me_id) {
	$_->name('poco/@me/@all/{id}');
	$_->to(
	  cb => sub {
	    my $c = shift;
	    return $plugin->serve($c => $c->stash('id'));
	  });
      };

      # Add route /@me/@self
      $route->route('/@me/@self')->name('poco/@me/@self')->to(
	cb => sub {
	  my $c = shift;
	  return $plugin->serve($c => $c->stash('poco.user_id'));
	});

      return;
    });

  # Add 'poco' helper
  $mojo->helper('poco'        => sub { $plugin->read(shift, { @_ } );   } );
  $mojo->helper('render_poco' => sub { $plugin->render( @_ ); } );

  foreach my $action (qw/create update delete/) {
    $mojo->helper(
      $action . '_poco' => sub {
	$plugin->modify($action => @_ );
      });
  };
};


# Serve Portable Contacts
sub serve {
  my ($plugin, $c, $id) = @_;

  my $status   = 404;
  my $response;

  # Return single response for /@me/@self or /@me/@all/{id}
  if ($id) {

    $response = { entry => +{} };

    # Get results
    $plugin->read(
      $c => {
	$plugin->_get_param( %{$c->param->to_hash} ),
	id => $id
      }, $response );

    $status = 200 if $response->totalResults;
  }

  # Return multiple response for /@me/@all
  else {

    $response = { entry => [] };

    # Get results
    $plugin->read(
      $c => {
	$plugin->_get_param(%{$c->param->to_hash})
      },
      $response
    );

    # Request successfull
    $status = 200 if $response;
  };

  # Render poco
  return $plugin->render(
    $c     => _new_response($response),
    status => $status
  );
};


# Get PortableContacts
sub read {
  my ($plugin, $c, $param, $response) = @_;

  $response //= {};

  # Run 'get_poco' hook
  $c->app->plugins->emit_hook(
    'read_poco' => (
      $plugin,
      $c,
      $param,
      $response
    ));

  return _new_response($response);
};


# Render Portable Contacts
sub render {
  my ($plugin, $c, $response, @param) = @_;

  # content negotiation
  return $c->respond_to(
    xml => sub {
      $c->render(
	data   => $response->to_xml,
	format => 'xml',
	@param
      )},
    any => sub {
      $c->render(
	data   => $response->to_json,
	format => 'json',
	@param
      )});
};

# Filter for valid parameters
sub _get_param {
  my $plugin = shift;
  my %param  = @_;

  my %new_param;
  foreach my $cond (keys %CONDITIONS_RE) {
    if (exists $param{$cond} && !ref($param{$cond})) {

      # Valid
      if ($param{$cond} =~ $CONDITIONS_RE{$cond}) {
	$new_param{$cond} = $param{$cond};
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
  if (ref($_[0]) eq __PACKAGE__ . '::Response') {
    return $_[0];
  }

  # Create new response object
  else {
    return Mojolicious::Plugin::PortableContacts::Response->new(@_);
  };
};










# Change PortableContacts Entry
sub modify {
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
