package Mojolicious::Plugin::HostMeta;
use Mojo::Base 'Mojolicious::Plugin';
use Mojo::JSON;
use Storable 'dclone';

has 'host';
has 'secure' => 0;

our $WKPATH;
BEGIN {
    our $WKPATH = '/.well-known/host-meta';
};

# Register plugin
sub register {
    my ($plugin, $mojo, $param) = @_;

    # Load Util-Endpoint if not already loaded
    unless (exists $mojo->renderer->helpers->{'endpoint'}) {
	$mojo->plugin('Util::Endpoint');
    };

    # Load XRD if not already loaded
    unless (exists $mojo->renderer->helpers->{'new_xrd'}) {
	$mojo->plugin('XRD');
    };

    my $hostmeta = $mojo->new_xrd;
    
    # Discover relations
    # $mojo->helper( 'discover_rel' => \&discover_rel );

    # If domain parameter is given
    if ($param->{host}) {
	$plugin->host($param->{host});

	# Add host-information to host-meta
	$hostmeta->add(
	    'hm:Host',
	    {
		'hm:xmlns' =>
		    'http://host-meta.net/xrd/1.0'
	    },
	    $plugin->host
	    );
    };

    # use https or http
    $plugin->secure( $param->{secure} );

    # Establish 'hostmeta' helper
    $mojo->helper(
	'hostmeta' => sub {
	    my $c = shift;
	    
	    if (!$_[0]) {
		return $hostmeta;
	    } 
	    
	    elsif ($_[0] eq 'host') {
		return $plugin->host unless $_[1];
		return $plugin->host($_[1]);
	    };
	    
	    return $plugin->_get_hostmeta($c, @_);
	});
    
    
    # Establish /.well-known/host-meta route
    my $route = $mojo->routes->route($WKPATH);

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

	    # Maybe testing, if the hook will release anything
	    my $hostmeta_clone = dclone($hostmeta);

	    $c->app->plugins->run_hook(
		'before_serving_hostmeta',
		$c,
		$hostmeta_clone);

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
    $c->app->plugins->run_hook(
	'before_fetching_hostmeta',
	$c,
	$host,
	\$hostmeta_xrd
	);

    return $hostmeta_xrd if $hostmeta_xrd;

    # 1. Check https:, then http:
    my $host_hm_path = $host.$WKPATH;

    # Get user agent
    my $ua = $c->ua->max_redirects(3);
    $ua->name('Sojolicious on Mojolicious (Perl)');

    # Fetch Host-Meta XRD
    # First try ssl
    my $secure = 'https://';
    my $host_hm = $ua->get($secure.$host_hm_path);

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
	$c->new_xrd($host_hm->res->body);

    # Host validation is now deprecated

    # Hook for caching
    $c->app->plugins->run_hook(
	'after_fetching_hostmeta',
	$c,
	$host,
	\$hostmeta_xrd,
	$host_hm->res
	);

    # Return XRD DOM
    return $hostmeta_xrd;
};

1;

__END__

=pod

=head1 NAME

Mojolicious::Plugin::HostMeta

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
as an L<Mojolicious::Plugin::Hostmeta::Document> object,
if no hostname is given. If a hostname is given, the
corresponding hostmeta document is retrieved and returned
as an XRD object.

=head1 ROUTES

The route C</.well-known/host-meta> is established and serves
the host's own hostmeta document.

=head1 HOOKS

=over 2

=item C<before_serving_hostmeta>

  package Mojolicious::Plugin::Foo;
  use Mojo::Base 'Mojolicious::Plugin';

  sub register {
     my ($self, $mojo) = @_;
     $mojo->plugins->add_hook('before_hostmeta' => sub {
	my $plugins = shift;
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

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2011, Nils Diewald.

This program is free software, you can redistribute it
and/or modify it under the same terms as Perl.

=cut
