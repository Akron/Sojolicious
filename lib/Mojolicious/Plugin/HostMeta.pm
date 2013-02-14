package Mojolicious::Plugin::HostMeta;
use Mojo::Base 'Mojolicious::Plugin';
use Mojo::UserAgent;
use Mojo::JSON;
use Mojo::Util qw/quote/;

use Storable 'dclone';

use constant WK_PATH => '/.well-known/host-meta';

sub host   { warn 'host is deprecated'   };
sub secure { warn 'secure is deprecated' };


# Register plugin
sub register {
  my ($plugin, $mojo) = @_;

  my $helpers = $mojo->renderer->helpers;

  # Load Util-Endpoint if not already loaded
  unless (exists $helpers->{endpoint}) {
    $mojo->plugin('Util::Endpoint');
  };

  # Load XML if not already loaded
  unless (exists $helpers->{render_xrd}) {
    $mojo->plugin('XRD');
  };

  unless (exists $helpers->{new_hostmeta}) {
    $mojo->plugin('XML' => {
      new_hostmeta => [qw/XRD HostMeta/]
    });
  };

  my $hostmeta = $mojo->new_hostmeta;

  # Get host information on first request
  $mojo->hook(
    on_prepare_hostmeta =>
      sub {
	my ($plugin, $c, $xrd_ref) = @_;
	my $host = $c->req->url->host;

	# Add host-information to host-meta
	$hostmeta->add_host($host) if $host;
      }
    );

  # Establish 'hostmeta' helper
  $mojo->helper(
    hostmeta => sub {
      my $c = shift;

      unless ($_[0]) {

	# Return local host
	return $plugin->_prepare_and_serve($c, $hostmeta);
      }

      # Is host (which is deprecated)
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
  $route->endpoint('hostmeta');

  # Set route callback
  $route->to(
    cb => sub {
      my $c = shift;

      # resource parameter
      if (my $res = $c->param('resource')) {

	# LRDD
	if (exists $helpers->{lrdd}) {
	  my $xrd = $c->lrdd($res => 'localhost');
	  return $c->render_xrd($xrd) if $xrd;
	  return $c->render_xrd(undef, $res);
	};
      };

      return $c->render_xrd(
	$plugin->_prepare_and_serve($c, $hostmeta)
      );
    });
};


# Get HostMeta document
sub _get_hostmeta {
  my $plugin = shift;
  my $c = shift;

  my $host = lc(shift(@_));

  my ($param, $res, $rel) = (shift);

  my $secure = $_[0] && $_[0] eq '-secure' ? 1 : 0;

  my $res_param = do {
    if ($param) {
      $rel = $param->{rel};
      $res = $param->{resource};
    };
    $res ? '?resource=' . $res : '';
  };

  # Hook for caching
  my $hostmeta_xrd;
  $c->app->plugins->emit_hook(
    'before_fetching_hostmeta',
    $plugin,
    $c,
    $host,
    \$hostmeta_xrd
  );

  if ($hostmeta_xrd) {
    _filter_rel($hostmeta_xrd, $rel) if $rel;
    return $hostmeta_xrd;
  };

  # 1. Check https:, then http:
  my $host_hm_path = $host . WK_PATH;

  # Get user agent
  my $ua = Mojo::UserAgent->new(
    max_redirects => 3,
    name => 'Sojolicious on Mojolicious (Perl)'
  );

  # Fetch Host-Meta XRD
  # First try ssl
  my $host_hm = $ua->get('https://' . $host_hm_path . $res_param);

  #  unless ($host_hm->success) { ... };

  unless ($host_hm &&
	  $host_hm->res->is_status_class(200)) {

    if ($res && index($host_hm->res->content_type, 'application') == 0) {
      return undef;
    };

    return undef if $secure;

    # Then try insecure
    $host_hm = $ua->get('http://' . $host_hm_path . $res_param);

    unless ($host_hm &&
	    $host_hm->res->is_status_class(200)) {

      # No result
      return undef;
    };
  };

  # Parse XRD
  $hostmeta_xrd = $c->new_hostmeta($host_hm->res->body);

  my @hook_array = (
    $plugin,
    $c,
    $host,
    \$hostmeta_xrd,
    $host_hm->res
  );

  # Resource request
  if ($res && $hostmeta_xrd->at('Subject')->text eq $res) {
    my $helpers = $c->app->renderer->helpers;

    # LRDD exists
    if (exists $helpers->{lrdd}) {

      # Hook for caching
      $c->app->plugins->emit_hook(
	after_fetching_lrdd => @hook_array
      );
    };
  }

  # Common HostMeta request
  else {

    # Hook for caching
    $c->app->plugins->emit_hook(
      after_fetching_hostmeta => @hook_array
    );
  };

  _filter_rel($hostmeta_xrd, $rel) if $rel;

  # Return XRD DOM
  $hostmeta_xrd;
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
      $ophm => (
	$plugin,
	$c,
	$hostmeta
      ));

    # Unsubscribe all subscribers
    foreach (@{ $plugins->subscribers( $ophm ) }) {
      $plugins->unsubscribe($ophm => $_);
    };
  };

  # Clone hostmeta reference
  my $hostmeta_clone = dclone($hostmeta);

  # Emit 'before_serving_hostmeta' hook
  $plugins->emit_hook(
    before_serving_hostmeta => (
      $plugin,
      $c,
      $hostmeta_clone
    ));

  # Return hostmeta clone
  $hostmeta_clone;
};


# Filter link relations
sub _filter_rel {
  my ($xrd, $rel) = @_;
  my @rel = ref $rel ? @$rel : split(/\s+/, $rel);
  $rel = 'Link:' . join(':', map { 'not([rel=' . quote $_ . '])'} @rel);
  $xrd->find($rel)->each( sub{ $_->replace('') } );
};


1;


__END__

=pod

=head1 NAME

Mojolicious::Plugin::HostMeta - HostMeta Plugin for Mojolicious

=head1 SYNOPSIS

  # Mojolicious
  $self->plugin('HostMeta');

  # Mojolicious::Lite
  plugin 'HostMeta';

  # In Controllers
  print $self->hostmeta('gmail.com')->get_link('lrrd');

  print $self->endpoint('host_meta');

=head1 DESCRIPTION

L<Mojolicious::Plugin::HostMeta> is a plugin to support
"well-known" HostMeta documents
(see L<https://tools.ietf.org/html/rfc6415|RFC6415>).


=head1 METHODS

=head2 C<register>

  # Mojolicious
  $app->plugin('HostMeta');

  # Mojolicious::Lite
  plugin 'HostMeta';

Called when registering the plugin.


=head1 HELPERS

=head2 C<hostmeta>

  # In Controller:
  my $xrd = $self->hostmeta;
  $xrd = $self->hostmeta('gmail.com');
  $xrd = $self->hostmeta('sojolicio.us' => {
    resource => 'acct:akron@sojolicio.us',
    rel      => 'hub'
  });
  $xrd = $self->hostmeta('gmail.com', -secure);

The helper C<hostmeta> returns the own hostmeta document
as an L<Mojolicious::Plugin::XML::XRD> object with
L<Mojolicious::Plugin::XML::HostMeta> extension,
if no hostname is given.
If a hostname is given, the corresponding hostmeta document
is retrieved and returned as an XRD object.
In that case an additional hash reference is accepted
with C<resource> and C<rel> parameters (see the spec for explanation).

An additional C<-secure> flag indicates, that only discovery over
C<https> is allowed.

=head2 C<new_hostmeta>

  # In Controller:
  my $xrd = $self->new_hostmeta;

The helper C<new_hostmeta> returns a new L<MojoX::XML::XRD>
object with C<MojoX::XML::HostMeta> extension.


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
served. The hook returns the plugin object, the current
controller object and the hostmeta document.

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
This hook is NOT released after a successful resource request.
This can be used for caching.

=back

=head1 DEPENDENCIES

L<Mojolicious> (best with SSL support),
L<Mojolicious::Plugin::XRD>,
L<Storable>.

=head1 AVAILABILITY

  https://github.com/Akron/Sojolicious

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2011-2013, L<Nils Diewald|http://nils-diewald.de/>.

This program is free software, you can redistribute it
and/or modify it under the same terms as Perl.

=cut
