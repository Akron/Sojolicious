package Mojolicious::Plugin::Webfinger;
use strict;
use warnings;
use Mojo::Base 'Mojolicious::Plugin';
use Mojo::Util qw/url_escape/;

has 'host';
has secure => 0;

sub register {
    my ($plugin, $mojo, $param) = @_;

    # Load Host-Meta if not already loaded.
    # This automatically loads the 'XRD' plugin.
    unless (exists $mojo->renderer->helpers->{'hostmeta'}) {
	$mojo->plugin('host_meta', {'host' => $param->{'host'} });
    };

    if (defined $param->{host}) {
	$plugin->host($param->{host});
    } else {
	$plugin->host( $mojo->hostmeta('host') || 'localhost' );
    };

    $plugin->secure( $param->{secure} );

    if (exists $param->{template} ||
	exists $param->{href}) {
	my $lrdd = { rel => 'lrdd' };

	if (exists $param->{template}) {
	    $lrdd->{template} =
		$plugin->secure.
		$plugin->host.
		$param->{template};
	} else {
	    $lrdd->{href} =
		$plugin->secure.
		$plugin->host.
		$param->{href};
	};

	$plugin->add_to_hostmeta($mojo, $lrdd);
    };

    # Add 'webfinger' helper
    $mojo->helper(
	'webfinger' => sub {
	    return $plugin->_get_webfinger(@_);
	});

    # Add 'webfinger' shortcut
    $mojo->routes->add_shortcut(
	'webfinger' => sub {
	    my $route = shift;
	    my $param = shift;

	    my $lrdd = { rel => 'lrdd' };
	    
	    if ($param) {
		$param = { $param => '{uri}' };
	    };

	    $mojo->endpoint(
		'webfinger',
		$plugin->secure,
		$plugin->host,
		$route,
		$param
		);

	    my $endpoint = $mojo->endpoint('webfinger',
					   {'uri' => '{uri}'});
	    
	    if ($endpoint =~ m/\{(?:.+?)\}/) {
		$lrdd->{template} = $endpoint;
	    } else {
		$lrdd->{href} = $endpoint;
	    };

	    $plugin->_add_to_hostmeta($mojo, $lrdd);

	    $route->to(
		cb => sub {
		    my $c = shift;
		    my $uri = $c->stash('uri');

		    my $xrd = $plugin->_get_finger($c,$uri);

		    if ($xrd) {
			$c->render(
			    'format' => 'xrd',
			    'inline' => $xrd->to_xml
			    );
		    }
		    
		    # Not found
		    else {
			$c->render_not_found;
		    };
		}
	    );


	}
	);

};


sub _add_to_hostmeta {
    my $plugin = shift;
    my $mojo = shift;
    my $lrdd = shift;

    my $link = $mojo->hostmeta->add('Link', $lrdd);
    $link->comment('Webfinger');
    $link->add('Title','Resource Descriptor');
};


sub _get_webfinger {
    my $plugin = shift;
    my $c = shift;

    # Get user and domain
    my ($user, $domain) = $plugin->_get_account( shift );

    # Hook for caching
    my $acct_xrd;
    $c->app->plugins->run_hook(
	'before_fetching_webfinger',
	$c,
	'acct:'.$user.'@'.$domain,
	\$acct_xrd
	);
    return $acct_xrd if $acct_xrd;


    # Get host-meta from domain
    my $domain_hm = $c->hostmeta($domain);

    # No host-meta found
    return undef unless $domain_hm;
	
    # Returns a Mojo::DOM node
    my $lrdd = $domain_hm->get_link('lrdd')->[0];
	
    my $webfinger_uri;
	
    # Get webfinger uri by using template
    if ($webfinger_uri = $lrdd->attrs->{'template'}) {
	my $acct = 'acct:'.$user.'@'.$domain;
	url_escape $acct;
	$webfinger_uri =~ s/\{uri\}/$acct/;
    }
	
    # Get webfinger uri by using href
    elsif (not ($webfinger_uri = $lrdd->attrs->{'href'})) {
	return undef;
    };

    my $ua = $c->ua->max_redirects(3);

#    # If the Uri has no host-information:
#    # Problematic, when there was a redirect like at yahoo.com!
#    if ($webfinger_uri !~ /^https?:/) {
#	# Todo: Get xml:base
#        my $new_uri = Mojo::URL->new($webfinger_uri);
#	$new_uri->host($domain);
#	$new_uri->scheme('https');
#
#        if ($webfinger_uri =~ /^\//) {
#          
#        } else {
#
#	};
#
#	$acct_doc = $ua->get($new_uri);
#	if ($acct_doc) {
#	} else {
#	    $new_uri->scheme('http');
#	    # ...
#	};
#
#     } else {
	  
    my $acct_xrd_doc = $ua->get($webfinger_uri);
    if ($acct_xrd_doc &&
	$acct_xrd_doc->res->is_status_class(200)
	) {
	
	# Return Mojolicious::Plugin::XRD object
	$acct_xrd = $c->new_xrd($acct_xrd_doc->res->body);

	# Hook for caching
	$c->app->plugins->run_hook(
	    'after_fetching_webfinger',
	    $c,
	    'acct:'.$user.'@'.$domain,
	    \$acct_xrd,
	    $acct_xrd_doc->res
	    );
	return $acct_xrd;
	
    } else {
	
	# Found no webfinger document
	return undef;
    };


    # };

    $ua->max_redirects(0);
    
};

# Serve webfinger?
sub _get_finger {
    my $plugin = shift;
    my $c = shift;

    my ($user, $domain) = $plugin->_get_account( shift );

    $domain ||= $plugin->host;

    # Get local account data
    if (!$domain ||
	$domain eq $plugin->host) {

	my $wf_xrd = $c->new_xrd;
	$wf_xrd->add('Subject','acct:'.$user.'@'.$domain);

	# Run hook
	$c->app->plugins->run_hook(
	    'before_serving_webfinger',
	    $c,
	    'acct:'.$user.'@'.$domain,
	    $wf_xrd
	    );

	# Return webfinger document
	return $wf_xrd;

    } else {

	return undef;
    };
}

sub _get_account {
    my $plugin = shift;
    my $acct = shift;

    # Delete scheme if exists
    $acct =~ s/^acct://i;

    # Split user from domain
    my ($user, $domain) = split('@',$acct);

    $domain ||= $plugin->domain;

    return ($user, $domain);
};


1;

__END__

=head1 NAME

Mojolicious::Plugin::Webfinger - Webfinger Plugin

=head1 SYNOPSIS

  # Mojolicious
  $app->plugin('webfinger');

  my $r = $app->routes;
  $r->route('/webfinger/:uri')->webfinger;

  my $profile_page = 
    $c->webfinger('acct:bob@example.org')
        ->get_link('describedby')
        ->attrs->{'href'};

  # Mojolicious::Lite
  plugin 'webfinger';
  my $wf = any '/webfinger';
  $wf->webfinger;

=head1 DESCRIPTION

L<Mojolicious::Plugin::Webfinger> provides several functions for
the Webfinger Protocol (see L<http://code.google.com/p/webfinger/wiki/WebFingerProtocol|Specification>).

=head1 ATTRIBUTES

=head2 C<host>

  $wf->host('sojolicio.us');
  my $host = $wf->host;

The host for the webfinger domain.

=head2 C<secure>

  $wf->secure(1);
  my $sec = $wf->secure;

Use C<http> or C<https>.

=head1 HELPERS

=head2 C<webfinger>

    # In Controllers:
    my $xrd = $self->webfinger;
    my $xrd = $self->webfinger('acct:me@sojolicio.us');

Returns the Webfinger L<Mojolicious::Plugin::XRD> document.
If no account name is given, the user's own webfinger document
is returned.

=head1 SHORTCUTS

  $r->route('/test/:uri')->webfinger;
  # Webfinger at /test/{uri}

  $r->route('/test/')->webfinger('q');
  # Webfinger at /test/q={uri}

  $r->route('/test/')->webfinger;
  # Webfinger at /test/

L<Mojolicious::Plugin::Webfinger> provides a route shortcut
for serving a C<lrrd> Link relation in C</.well-known/host-meta>
(see L<Mojolicious::Plugin::HostMeta).

Please set a C<host> as well as the C<secure> parameter when
loading the plugin, so the path is correct.

  $app->plugin('webfinger',
               'host' => 'example.org',
               'secure' => 1)

=head1 HOOKS

=over 2

=item C<before_fetching_webfinger>

This hook is run before a webfinger account is fetched.
This is useful for chaching. The hook returns the current
??? object, the account name and an empty string reference,
meant to refer to the xrd_object.
If the XRD reference is filled, the fetching will not proceed. 

=item C<after_fetching_webfinger>

This hook is run after a webfinger document is retrieved.
This can be used for caching.
The hook returns the current ??? object, the account name,
a string reference, meant to refer to the XRD object, and the
L<Mojo::Message::Response> object from the request. 

=back

=head1 DEPENDENCIES

L<Mojolicious> (best with SSL support),
L<Mojolicious::Plugin::HostMeta>.

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2011, Nils Diewald.

This program is free software, you can redistribute it
and/or modify it under the same terms as Perl.

=cut
