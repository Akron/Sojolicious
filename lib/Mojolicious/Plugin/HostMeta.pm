package Mojolicious::Plugin::HostMeta;
use strict;
use warnings;
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

    # Load XRD if not already loaded
    unless (exists $mojo->renderer->helpers->{'new_xrd'}) {
	$mojo->plugin('x_r_d');
    };

    my $hostmeta = $mojo->new_xrd;

    # Establish 'endpoint' helper
    my %endpoint;
    $mojo->helper(
	'endpoint' => sub {
	    my $c = shift; # c or mojo
	    my $name = shift;
	    
	    my $hash_param = {};
	    if (ref($c) eq 'Mojolicious::Controller') {
		%{$hash_param} = %{$c->stash};
	    };

	    # Get endpoint url
	    if (!defined $_[1]) {
		if ($_[0]) {
		    my $h = shift;
		    foreach (keys %$h) {
			$hash_param->{$_} = $h->{$_}
		    };
		};

		my $url = $c->url_for( $name,
				       $hash_param )->to_abs;

		if (exists $endpoint{$name}) {
		    my $new_url = $endpoint{$name}->clone;
		    $url = $new_url->path($url->path);
		};
		my $endpoint = $url->to_string;
		$endpoint =~ s/%7B(.+?)%7D/{$1}/g;
		return $endpoint;
	    }
	    
	    # Define endpoint url
	    else {

		my ($secure, $host, $route, $param) = @_;

		if (exists $endpoint{$name}) {
		    warn qq{Route $name already defined.};
		    return;
		};

		my $endpoint = Mojo::URL->new;
		for ($endpoint) {
		    $_->host( $host );
		    $_->scheme( $secure ? 'https' : 'http' );
		    $_->query->param( %$param ) if $param;
		    $endpoint{$name} = $_;
		};

		$route->name($name);
	    };
	});

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
		return $plugin->host if !$_[1];
		return $plugin->host($_[1]);
	    };

	    return $plugin->_get_hostmeta($c, @_);
	}
	);


    # Establish /.well-known/host-meta route
    my $route = $mojo->routes->route($WKPATH);

    # Define endpoint manually (Really necessary?)
    $route->name('hostmeta');
    my $endpoint = Mojo::URL->new;
    $endpoint->host( $plugin->host );
    $endpoint->scheme( $plugin->secure ? 'https' : 'http' );
    $endpoint{hostmeta} = $endpoint;

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
	}
	);
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

    $hostmeta_xrd->url_for($secure.$WKPATH);

    # Validate host
    if (my $host_e = $hostmeta_xrd->dom->at('Host')) {
	if ($host_e->namespace eq 'http://host-meta.net/xrd/1.0') {

	    # Is the given domain the expected one?
	    if (lc($host_e->text) ne $host) {
		$c->app->log->info('The domains "'.$host.'"'.
			      ' and "'.$host_e->text.'" do not match.');
		return undef;
	    };
	};
    };

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
  $self->plugin('host_meta', { 'host' => 'sojolicio.us' } );

  # Mojolicious::Lite
  plugin 'host_meta';
  plugin host_meta => { host => 'sojolicio.us' };

  # In Controllers
  print $self->hostmeta('gmail.com')->get_link('lrrd');

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

=head2 C<endpoint>

  # In Application:
  my $route = $mojo->routes->route('/:user/webfinger');
  $mojo->endpoint('webfinger' => 1,             # https
                                 'sojolicio.us' # host
                                 $route         # Route
                                 );

  # In Controller:
  $self->

=head1 ROUTES

The route C</.well-known/host-meta> is established an serves
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
	$hostmeta->add('Link', {rel => 'try'} );
  };

This hook is run before the host's own hostmeta document is
served. The hook returns the current ??? object and the hostmeta
document.

=item C<before_fetching_hostmeta>

This hook is run before a foreign hostmeta document is retrieved.
This can be used for caching.
The hook returns the current ??? object, the host name, and an empty
string reference, meant to refer to the XRD object.
If the XRD reference is filled, the fetching will not proceed. 

=item C<after_fetching_hostmeta>

This hook is run after a foreign hostmeta document is retrieved.
This can be used for caching.
The hook returns the current ??? object, the host name, a string
reference, meant to refer to the XRD object, and the
L<Mojo::Message::Response> object from the request. 

=back

=head1 DEPENDENCIES

L<Mojolicious> (best with SSL support),
L<Mojolicious::Plugin::XRD>.

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2011, Nils Diewald.

This program is free software, you can redistribute it
and/or modify it under the same terms as Perl.

=cut
