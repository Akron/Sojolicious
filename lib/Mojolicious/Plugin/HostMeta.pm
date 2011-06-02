package Mojolicious::Plugin::HostMeta;
use strict;
use warnings;
use Mojo::Base 'Mojolicious::Plugin';
use Storable 'dclone';

has 'host';

# Register plugin
sub register {
    my ($plugin, $mojo, $param) = @_;

    # Load XRD if not already loaded
    unless (exists $mojo->renderer->helpers->{'new_xrd'}) {
	$mojo->plugin('x_r_d');
    };

    my $hostmeta = $mojo->new_xrd;

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
	    }

	    return $plugin->get_hostmeta($c, @_);
	}
	);


    # Establish /.well-known/host-meta route
    $mojo->routes->route('/.well-known/host-meta')->to(
	cb => sub {
	    my $c = shift;

	    # Maybe testing, if the hook will release anything
	    my $hostmeta_clone = dclone($hostmeta);

	    $c->app->plugins->run_hook(
		'before_serving_hostmeta',
		$c,
		$hostmeta_clone);

	    $c->render(
		'inline' => $hostmeta_clone->to_xml,
		'format' => 'xrd'
		)
	}
	);
};

sub get_hostmeta {
    my $plugin = shift;
    my $c = shift;

    my $domain = lc(shift(@_));

    # Hook for caching
    my $hostmeta_xrd;
    $c->app->plugins->run_hook(
	'before_fetching_hostmeta',
	$c,
	$domain,
	\$hostmeta_xrd
	);
    return $hostmeta_xrd if $hostmeta_xrd;

    # 1. Check https:, then http:
    my $domain_hm_path = $domain.'/.well-known/host-meta';

    # Get user agent
    my $ua = $c->ua->max_redirects(3);
    $ua->name('Sojolicious on Mojolicious (Perl)');

    # Fetch Host-Meta XRD
    # First try ssl
    my $domain_hm = $ua->get('https://'.$domain_hm_path);

    if (!$domain_hm ||
	!$domain_hm->res->is_status_class(200)
	) {
	
	# Then try insecure
	$domain_hm = $ua->get('http://'.$domain_hm_path);

	if (!$domain_hm ||
	    !$domain_hm->res->is_status_class(200)
	    ) {

	    # Reset max_redirects
	    $ua->max_redirects(0);
	
	    # No result
	    return undef;
	};
    };

    # Parse XRD
    $hostmeta_xrd =
	$c->new_xrd($domain_hm->res->body);

    # Validate host
    if (my $host = $hostmeta_xrd->dom->at('Host')) {
	if ($host->namespace eq 'http://host-meta.net/xrd/1.0') {

	    # Is the given domain the expected one?
	    if (lc($host->text) ne $domain) {
		$c->app->log->info('The domains "'.$domain.'"'.
			      ' and "'.$host->text.'" do not match.');
		return undef;
	    };
	};
    };


    # Hook for caching
    $c->app->plugins->run_hook(
	'after_fetching_hostmeta',
	$c,
	$domain,
	\$hostmeta_xrd,
	$domain_hm->res
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
"well-known" HostMeta documents (see L<http://tools.ietf.org/html/draft-hammer-hostmeta|Specification>).

=head1 HELPERS

=head2 C<hostmeta>

    # In Controllers:
    my $xrd = $self->hostmeta;
    my $xrd = $self->hostmeta('gmail.com');

The helper C<hostmeta> returns the own hostmeta document
as an L<Mojolicious::Plugin::XRD> object, if no hostname
is given. If a hostname is given, the corresponding
hostmeta document is retrieved and returned as an XRD
object.

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

L<Mojolicious>, L<Mojolicious::Plugin::XRD>.

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2011, Nils Diewald.

This program is free software, you can redistribute it
and/or modify it under the same terms as Perl.

=cut
