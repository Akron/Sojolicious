package Mojolicious::Plugin::HostMeta;
use Mojo::Base 'Mojolicious::Plugin';
use Mojo::JSON;
use Storable 'dclone';

has 'host';
has 'secure' => 0;

use constant WK_PATH => '/.well-known/host-meta';

# Register plugin
sub register {
  my ($plugin, $mojo, $param) = @_;

  my $helpers = $mojo->renderer->helpers;

  # Load Util-Endpoint if not already loaded
  unless (exists $helpers->{'endpoint'}) {
    $mojo->plugin('Util::Endpoint');
  };

  # Load XML if not already loaded
  unless (exists $helpers->{'render_xrd'}) {
    $mojo->plugin('XRD');
  };

  unless (exists $helpers->{'new_hostmeta'}) {
    $mojo->plugin('XML' => {
      new_hostmeta => ['XRD', 'HostMeta']
    });
  };

  my $hostmeta = $mojo->new_hostmeta;

  # If domain parameter is given
  if ($param->{host}) {
    $plugin->host($param->{host});

    # Add host-information to host-meta
    $hostmeta->add_host($plugin->host);
  }

  # Get host information on first request
  else {
    $mojo->hook(
      'on_prepare_hostmeta' =>
	sub {
	  my ($plugin, $c, $xrd_ref) = @_;
	  my $host = $c->req->url->host;
	  if ($host) {
	    $plugin->host($host);

	    # Add host-information to host-meta
	    $hostmeta->add_host($host);
	  }
	});
  };

  # use https or http
  $plugin->secure( $param->{secure} );

  # Establish 'hostmeta' helper
  $mojo->helper(
    'hostmeta' => sub {
      my $c = shift;

      if (!$_[0]) {

	return $plugin->_prepare_and_serve($c, $hostmeta);
      }

      elsif ($_[0] eq 'host') {
	warn "->hostmeta('host') is DEPRECATED!";
	return $plugin->host unless $_[1];
	return $plugin->host($_[1]);
      };

      return $plugin->_get_hostmeta($c, @_);
    });

  # Establish /.well-known/host-meta route
  my $route = $mojo->routes->route( WK_PATH );

  # Define endpoint
  $route->endpoint(
    'hostmeta' => {
      scheme => $plugin->secure ? 'https' : 'http',
      host   => $plugin->host,
    });

  # Set route callback
  $route->to(
    cb => sub {
      my $c = shift;

      my $hostmeta_clone = $plugin->_prepare_and_serve($c, $hostmeta);
      return $c->render_xrd($hostmeta_clone);
    });


#    $mojo->routes->route('/')->bridge(
#	sub {
#	    my $c = shift;
#	    my $format = shift( @{ $mojo->types->detect(
#				       $c->req->headers->accept
#				       )});
#	    if ($format eq $mojo->types('xrd')) {
#		return 1;
#	    };
#	    return 0;
#	} )->redirect_to(...)

};


# Get HostMeta document
sub _get_hostmeta {
  my $plugin = shift;
  my $c = shift;

  my $host = lc(shift(@_));

  # Hook for caching
  my $hostmeta_xrd;
  $c->app->plugins->emit_hook(
    'before_fetching_hostmeta',
    $plugin,
    $c,
    $host,
    \$hostmeta_xrd
  );

  return $hostmeta_xrd if $hostmeta_xrd;

  # 1. Check https:, then http:
  my $host_hm_path = $host . WK_PATH;

  # Get user agent
  my $ua = $c->ua->max_redirects(3);
  $ua->name('Sojolicious on Mojolicious (Perl)');

  # Fetch Host-Meta XRD
  # First try ssl
  my $secure = 'https://';
  my $host_hm = $ua->get($secure . $host_hm_path);

  if (!$host_hm ||
	!$host_hm->res->is_status_class(200)
      ) {

    # Then try insecure
    $secure = 'http://';
    $host_hm = $ua->get($secure.$host_hm_path);

    if (!$host_hm ||
	  !$host_hm->res->is_status_class(200)
	) {

      # Reset max_redirects
      $ua->max_redirects(0);

      # No result
      return undef;
    };
  };

  # Parse XRD
  $hostmeta_xrd =
    $c->new_hostmeta($host_hm->res->body);

  # Host validation is now deprecated

  # Hook for caching
  $c->app->plugins->emit_hook(
    'after_fetching_hostmeta',
    $plugin,
    $c,
    $host,
    \$hostmeta_xrd,
    $host_hm->res
  );

  # Return XRD DOM
  return $hostmeta_xrd;
};


# Run hooks for preparation and serving of hostmeta
sub _prepare_and_serve {
  my ($plugin,
      $c,
      $hostmeta) = @_;

  my $plugins = $c->app->plugins;
  my $ophm = 'on_prepare_hostmeta';

  # Emit on_prepare_hostmeta only once
  if ($plugins->has_subscribers( $ophm )) {
    $plugins->emit_hook(
      $ophm =>
	($plugin,
	 $c,
	 $hostmeta));

    # Unsubscribe all subscribers
    foreach (@{$plugins->subscribers( $ophm )}) {
      $plugins->unsubscribe($ophm => $_);
    };
  };

  # Clone hostmeta reference
  my $hostmeta_clone = dclone($hostmeta);

  $plugins->emit_hook(
    'before_serving_hostmeta' =>
      ($plugin,
       $c,
       $hostmeta_clone));

  return $hostmeta_clone;
};

1;

__END__

=pod

=head1 NAME

Mojolicious::Plugin::HostMeta - HostMeta Plugin for Mojolicious

=head1 SYNOPSIS

  # Mojolicious
  $self->plugin('HostMeta', { 'host' => 'sojolicio.us' } );

  # Mojolicious::Lite
  plugin 'HostMeta';
  plugin HostMeta => { host => 'sojolicio.us' };

  # In Controllers
  print $self->hostmeta('gmail.com')->get_link('lrrd');

  print $self->endpoint('host_meta');

=head1 DESCRIPTION

L<Mojolicious::Plugin::HostMeta> is a plugin to support 
"well-known" HostMeta documents
(see L<http://tools.ietf.org/html/draft-hammer-hostmeta|Specification>).

=head1 ATTRIBUTES

=head2 C<host>

  $hm->host('sojolicio.us');
  my $host = $hm->host;

The host for the hostmeta domain.

=head2 C<secure>

  $hm->secure(1);
  my $sec = $hm->secure;

Use C<http> or C<https>.

=head1 HELPERS

=head2 C<hostmeta>

  # In Controller:
  my $xrd = $self->hostmeta;
  my $xrd = $self->hostmeta('gmail.com');

The helper C<hostmeta> returns the own hostmeta document
as an L<Mojolicious::Plugin::XML::XRD> object with
L<Mojolicious::Plugin::XML::HostMeta> extension,
if no hostname is given.
If a hostname is given, the corresponding hostmeta document
is retrieved and returned as an XRD object.

=head2 C<new_hostmeta>

  # In Controller:
  my $xrd = $self->new_hostmeta;

The helper C<new_hostmeta> returns a new L<Mojolicious::Plugin::XML::XRD>
object with C<Mojolicious::Plugin::XML::HostMeta> extension.

=head1 ROUTES

The route C</.well-known/host-meta> is established and serves
the host's own hostmeta document.

=head1 HOOKS

=over 2

=item C<on_prepare_hostmeta>

  package Mojolicious::Plugin::Foo;
  use Mojo::Base 'Mojolicious::Plugin';

  sub register {
     my ($self, $mojo) = @_;
     $mojo->hook('on_prepare_hostmeta' => sub {
	my $plugin = shift;
        my $c = shift;
	my $hostmeta = shift;
	$hostmeta->add_link('permanent');
  };

This hook is run when the host's own hostmeta document is
prepared. The hook passes the plugin object, the current controller
object and the hostmeta document.
This hook is only emitted once for each subscriber.

=item C<before_serving_hostmeta>

  package Mojolicious::Plugin::Foo;
  use Mojo::Base 'Mojolicious::Plugin';

  sub register {
     my ($self, $mojo) = @_;
     $mojo->hook('before_serving_hostmeta' => sub {
	my $plugin = shift;
        my $c = shift;
	my $hostmeta = shift;
	$hostmeta->add_link('try');
  };

This hook is run before the host's own hostmeta document is
served. The hook returns the current ??? object and the hostmeta
document.

=item C<before_fetching_hostmeta>

This hook is run before a foreign hostmeta document is retrieved.
The hook returns the current controller object, the host name,
and an empty string reference meant to refer to the XRD object.
If the XRD reference is filled, the fetching will not proceed. 
This can be used for caching.

=item C<after_fetching_hostmeta>

This hook is run after a foreign hostmeta document is retrieved.
The hook returns the current controller object, the host name,
a string reference meant to refer to the XRD object, and the
L<Mojo::Message::Response> object from the request.
This can be used for caching.

=back

=head1 DEPENDENCIES

L<Mojolicious> (best with SSL support),
L<Mojolicious::Plugin::XRD>.

=head1 AVAILABILITY

  https://github.com/Akron/Sojolicious

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2011, Nils Diewald.

This program is free software, you can redistribute it
and/or modify it under the same terms as Perl.

=cut
