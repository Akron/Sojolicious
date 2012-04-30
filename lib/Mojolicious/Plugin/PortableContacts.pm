package Mojolicious::Plugin::PortableContacts;
use Mojo::Base 'Mojolicious::Plugin';

# Load Response and Entry objects
use Mojolicious::Plugin::PortableContacts::Response;
use Mojolicious::Plugin::PortableContacts::Entry;

# Default count parameter
# TODO: Make ->poco PortableContact Server as well as Client
# TODO: Check OAuth2 and fill $c->stash->{'poco.user_id'} -> poco.user_id
# TODO: Updates via http://www.w3.org/TR/2011/WD-contacts-api-20110616/
# TODO: Support all error codes

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
      $route->endpoint('poco');

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
      my $me_all = $route->route('/');

      for ($me_all) {
	$_->name('poco/@me/@all-1');

	# Implicit Route
	$_->to(
	  cb => sub {
	    $plugin->serve( shift );
	  });
      };

      $me_all = $route->route('/@me/@all');

      for ($me_all) {
	$_->name('poco/@me/@all-2');

	# Explicit Route
	$_->to(
	  cb => sub {
	    $plugin->serve( shift );
	  });
      };

      # Add route /@me/@all/{id}
      my $me_id = $route->route('/@me/@all/:id'); # , id => qr/^[1-9]\d*$/);
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
	  return $plugin->serve($c => $c->stash('poco.user_id') || 0);
	});

      return;
    });

  # Add 'poco' helper
  $mojo->helper(
    poco => sub {
      $plugin->read(shift, { @_, internal => 1 } );
    });

  # Add render_poco helper
  $mojo->helper(
    render_poco => sub {
      $plugin->render( @_ );
    });
};


# Serve Portable Contacts
sub serve {
  my ($plugin, $c, $id) = @_;

  # 'Not found' is default
  my $status   = 404;

  # Empty response
  my $response = {
    totalResults  => 0,
    itemsPerPage => 0
  };

  my $param = $c->param ? $c->param->to_hash : {};

  # Return single response for /@me/@self or /@me/@all/{id}
  if (defined $id) {

    # Response is an entry hash
    $response->{entry} = {};

    # id is not null
    if ($id) {
      # Get results
      $plugin->read(
	$c => {
	  $plugin->_get_param( %$param ),
	  id => $id
	}, $response );

      $status = 200 if $response->{totalResults};
    };
  }

  # Return multiple response for /@me/@all
  else {

    # Response is an entry array
    $response->{entry} = [];

    # Get results
    $plugin->read(
      $c => {
	$plugin->_get_param(%$param)
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
	$count = delete $new_param{count};
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
  index(ref($_[0]), __PACKAGE__) != 0 ?
         Mojolicious::Plugin::PortableContacts::Response->new(@_) : $_[0];
};


1;


__END__

=pod

=head1 NAME

Mojolicious::Plugin::PortableContacts - PortableContacts Plugin

=head1 SYNOPSIS

  # Mojolicious
  $app->plugin('PortableContacts' => { count => 20 });

  # Mojolicious::Lite
  plugin PortableContacts => { count => 20 };

  # In Controller
  my $response = $c->poco(
    filterBy    => 'name.givenName',
    filterOp    => 'startswith',
    filterValue => 'Ak',
    fields      => 'name,birthday'
  );

  print $response->entry->[0]->to_xml;

  return $c->render_poco($response);

=head1 DESCRIPTION

L<Mojolicious::Plugin::PortableContacts> provides tools for
the L<PortableContacts API|http://portablecontacts.net/draft-spec.html>.

This plugin is database agnostic. Communication with a datastore
can be enabled via Hooks.

=head1 ATTRIBUTES

=head2 C<count>

  $pc->count(1);
  my $count = $pc->count;

Default and maximum number of items per page.
Defaults to 0, which means that there is no limit.

=head1 HELPERS

=head2 C<poco>

  # In Controller:
  my $response = $c->poco(
    filterBy    => 'name.givenName',
    filterOp    => 'startswith',
    filterValue => 'Ak',
    fields      => 'name,birthday'
  );

The helper C<poco> returns the result set of a PortableContacts
Query as a L<Mojolicious::Plugin::PortableContacts::Response> object.
The minimal set of possible parameters are described
in the L<Draft Spec|http://portablecontacts.net/draft-spec.html>.
In addition to that, user ids (as in /@me/@all/{id}) should be
provided as C<id =E<gt> {id}>.

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

=item C<read_poco>

This hook is run to retrieve the PortableContacts query result set
from a data store.
The hook passes the current plugin object, the current Controller object,
the query parameters as a hash reference and an empty
L<Mojolicious::Plugin::PortableContacts::Response> object, expected to
be filled with the requested result set.
In addition to the query an C<internal> parameter with a true value is
appended, if the hook was emitted from the helper instead of the route.

=back

=head1 DEPENDENCIES

L<Mojolicious>,
L<Mojolicious::Plugin::HostMeta>.

=head1 AVAILABILITY

  https://github.com/Akron/Sojolicious

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2011-2012, Nils Diewald.

This program is free software, you can redistribute it
and/or modify it under the same terms as Perl.

=cut
