package Mojolicious::Plugin::LRDD;
use Mojo::Base 'Mojolicious::Plugin';
use Mojo::ByteStream 'b';

# Register Plugin
sub register {
  my ($plugin, $mojo, $param) = @_;

  # Load Host-Meta if not already loaded.
  # This automatically loads the XRD and Endpoints plugins.
  unless (exists $mojo->renderer->helpers->{'hostmeta'}) {
    $mojo->plugin('HostMeta');
  };

  # lrdd helper
  $mojo->helper(
    lrdd => sub {
      my ($c, $ressource, $host) = @_;

      # Get host information based on ressource
      unless ($host) {
	$host = Mojo::URL->new( $ressource );
	return unless $host;
	$host = $host->host;
      };

      # Return xrd document
      return $plugin->_get_lrdd($c, $ressource => $host );
    });

  # Add 'lrdd' shortcut
  $mojo->routes->add_shortcut(
    'lrdd' => sub {
      my ($route, $param_key) = @_;

      # Set endpoint-uri
      $route->endpoint(
	'lrdd' => {
	  query  => $param_key ? [ $param_key => '{uri}' ] : undef
	});

      # Add Route to Hostmeta
      $mojo->hook(
	before_serving_hostmeta => sub {
	  my ($hm_plugin, $c, $hostmeta) = @_;

	  # Retrieve Endpoint-Uri
	  my $endpoint = $c->endpoint('lrdd');

	  # Create lrdd link attributes
	  my $lrdd = { type => 'application/xrd+xml' };

	  # If It's a template, point the lrdd to it
	  my $type = index($endpoint, '{uri}') > 0 ? 'template' : 'href';
	  $lrdd->{$type} = $endpoint;

	  $hostmeta->add_link('lrdd' => $lrdd)
	    ->comment('Link-based Resource Descriptor Discovery')
	      ->add('Title','Resource Descriptor');
	});

      # Point the route to a callback
      $route->to(
	cb => sub {
	  my $c = shift;

	  # Get uri from route
	  my $uri = $c->stash('uri');
	  $uri = $c->param($param_key) if ($param_key && !$uri);

	  my $ok = 0;

	  # Emit 'on_prepare_lrdd' hook
	  $mojo->plugins->emit_hook(
	    'on_prepare_lrdd' => (
	      $plugin, $c, $uri, \$ok
	    ));

	  # If already rendered do nothing
	  return if $c->req->body;

	  # uri was not resolved
	  return $c->render_not_found unless $ok;

	  # Get local xrd document
	  my $xrd = $plugin->_serve_lrdd($c, $uri);

	  # Serve local XRD document
	  return $c->render_xrd($xrd) if $xrd;

	  # Not found
	  return $c->render_not_found;
	});
    });
};

# Fetch ressource
sub _get_lrdd {
  my $plugin = shift;
  my $c      = shift;

  my ($ressource, $host) = @_;

  # Serve, if the request is local
  if ($host ~~ [$c->req->url->host, 'localhost']) {
    return $plugin->_serve_lrdd($c, $ressource);
  };

  # Hook for caching
  my $lrdd_xrd;
  $c->app->plugins->emit_hook(
    'before_fetching_lrdd' =>
      ($plugin, $c, $ressource, $host, \$lrdd_xrd )
    );

  # Serve XRD from cache
  return $lrdd_xrd if $lrdd_xrd;

  # Get host-meta from domain
  my $domain_hm = $c->hostmeta($host);

  # No host-meta found
  return undef unless $domain_hm;

  # Returns a Mojo::DOM node
  my $lrdd = $domain_hm->get_link('lrdd');

  # Get uri by using template
  my $uri;
  if ($uri = $lrdd->{'template'}) {
    my $res = b($ressource)->url_escape;
    $uri =~ s/\{uri\}/$res/;
  }

  # Get uri by using href
  elsif (not ($uri = $lrdd->{'href'})) {
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

  # lrdd XRD document
  my $lrdd_xrd_doc = $ua->get($uri);

  # lrdd request was a success
  if ($lrdd_xrd_doc &&
	$lrdd_xrd_doc->res->is_status_class(200)) {

    # Return Mojolicious::Plugin::XRD object
    $lrdd_xrd = $c->new_xrd($lrdd_xrd_doc->res->body);
  };

  # Hook for caching
  $c->app->plugins->emit_hook(
    'after_fetching_lrdd'=> (
      $plugin,
      $c,
      $ressource,
      $host,
      $lrdd_xrd,
      $lrdd_xrd_doc->res
    ));

  # Retrieved document is no XRD
  return undef unless $lrdd_xrd;

  # Return lrdd document
  return $lrdd_xrd;
};


# Serve LRDD
sub _serve_lrdd {
  my $plugin = shift;
  my $c = shift;
  my $uri = shift;

  # New xrd
  my $lrdd_xrd = $c->new_xrd;
  $lrdd_xrd->add('Subject' => $uri);

  # Run hook
  $c->app->plugins->emit_hook(
    'before_serving_lrdd' => (
      $plugin, $c, $uri, $lrdd_xrd
    ));

  return $lrdd_xrd;
};


1;

__END__

=head1 NAME

Mojolicious::Plugin::LRDD - Link-based Resource Descriptor Discovery

=head1 SYNOPSIS

  # Mojolicious
  $app->plugin('LRDD');

  my $r = $app->routes;
  $r->route('/lrdd')->lrdd('uri');

  my $profile_page =
    $c->lrdd('http://bob.example.org')
        ->get_link('describedby')
        ->attrs->{'href'};

  # Mojolicious::Lite
  plugin 'LRDD';
  (any '/lrdd')->lrdd('uri');


=head1 SHORTCUTS

=head2 C<lrdd>

  $r->route('/test/:uri')->lrdd;
  # LRDD at /test/{uri}

  $r->route('/test/')->lrdd('q');
  # LRDD at /test/q={uri}

  $r->route('/test/')->lrdd;
  # LRDD at /test/

L<Mojolicious::Plugin::LRDD> provides a route shortcut
for serving a C<lrdd> Link relation in C</.well-known/host-meta>
(see L<Mojolicious::Plugin::HostMeta).

=head1 HOOKS

=over 2

=item C<before_fetching_lrdd>

  $mojo->hook(
    'before_fetching_lrdd' => sub {
      my ($plugin,
          $c,
          $ressource,
          $host,
          $lrdd_xrd_ref) = @_;
      my $xrd = $c->new_xrd;
      $xrd->add('Subject => 'me');
      $$lrdd_xrd_ref = $xrd;
    });

This hook is run before a link-based ressource descriptor document
is fetched. This is useful for caching. The hook passes the plugin object,
the current controller object, the ressource identifier,
the host to ask for the ressource, and an empty string reference,
meant to refer to the xrd_object.
If the XRD reference is filled, the fetching will not proceed.

=item C<after_fetching_lrdd>

  $mojo->hook(
    'after_fetching_lrdd' => sub {
	my ($plugin,
	    $c,
	    $ressource,
	    $lrdd_xrd,
            $lrdd_response) = @_;
       print $lrdd_xrd->to_pretty_xml;
      });

This hook is run after a ressource descriptor document is
retrieved. This can be used for caching.
The hook passes the plugin object, the current controller object,
the ressource identifier, a string reference, meant to refer to
the XRD object, and the L<Mojo::Message::Response> object from the request.

=item C<on_prepare_lrdd>

  $mojo->hook(
    'on_prepare_lrdd' => (
      my ($plugin, $c, $ressource, $ok_ref) = @_;
      if ($ressource eq 'http://sojolicio.us/catz') {
        $$ok_ref = 1;
      };
  ));

This hook is run on the preparation of serving
a lrdd document. The hook passes the plugin object,
the current controller object, the identifier of the
ressource and a scalar reference.
If a ressource description exists for a given ressource,
the scalar of the scalar reference should be set to true.
The serving process will be stopped, if content was already
rendered and not found will be rendered, if the scalar
reference is false.

=item C<before_serving_lrdd>

  $mojo->hook(
    'before_serving_lrdd' => sub {
      my ($plugin, $c, $ressource, $lrdd_xrd) = @_;
      $lrdd_xrd->add_link('hcard' => { href => '/me.hcard' } );
    });

This hook is run before the XRD document is served.
The hook passes the plugin object, the current controller object,
the identifier of the ressource and the XRD object.

=back

=head1 DEPENDENCIES

L<Mojolicious> (best with SSL support),
L<Mojolicious::Plugin::HostMeta>.

=head1 AVAILABILITY

  https://github.com/Akron/Sojolicious

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2011, Nils Diewald.

This program is free software, you can redistribute it
and/or modify it under the same terms as Perl.

=cut
