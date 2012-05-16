package Mojolicious::Plugin::LRDD;
use Mojo::Base 'Mojolicious::Plugin';
use Mojo::ByteStream 'b';

# Register Plugin
sub register {
  my ($plugin, $mojo) = @_;

  # Load Host-Meta if not already loaded.
  # This automatically loads the XRD and Endpoints plugins.
  unless (exists $mojo->renderer->helpers->{'hostmeta'}) {
    $mojo->plugin('HostMeta');
  };


  # lrdd helper
  $mojo->helper(
    lrdd => sub {
      my ($c, $resource, $host) = @_;

      # Get host information based on resource
      unless ($host) {
	$host = Mojo::URL->new( $resource );
	return unless $host;
	$host = $host->host;
      };

      # Return xrd document
      return $plugin->_get_lrdd($c, $resource => $host );
    });


  # Add 'lrdd' shortcut
  $mojo->routes->add_shortcut(
    lrdd => sub {
      my ($route, $param_key) = @_;

      # Set endpoint-uri
      $route->endpoint(
	lrdd => {
	  query  => $param_key ? [ $param_key => '{uri}' ] : undef
	});


      # Add Route to Hostmeta - exactly once
      $mojo->hook(
	on_prepare_hostmeta => sub {
	  my ($hm_plugin, $c, $hostmeta) = @_;

	  # Retrieve Endpoint-Uri
	  my $endpoint = $c->endpoint('lrdd');

	  # Create lrdd link attributes
	  my $lrdd = { type => 'application/xrd+xml' };

	  # If It's a template, point the lrdd to it
	  my $type = index($endpoint, '{uri}') >= 0 ? 'template' : 'href';
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

	  return $plugin->_prepare_and_serve($c, $uri)
	});
    });
};


# Fetch resource
sub _get_lrdd {
  my $plugin = shift;
  my $c      = shift;

  my ($resource, $host) = @_;

  # Serve, if the request is local
  if ($host ~~ ['localhost', $c->req->url->host]) {
    if ($plugin->_prepare($c, $resource)) {
      return $plugin->_serve($c, $resource);
    };
    return;
  };

  # Hook for caching
  my $lrdd_xrd;
  $c->app->plugins->emit_hook(
    before_fetching_lrdd =>
      ($plugin, $c, $resource, $host, \$lrdd_xrd )
    );

  # Serve XRD from cache
  return $lrdd_xrd if $lrdd_xrd;

  # Get host-meta from domain
  my $domain_hm = $c->hostmeta($host => {
    resource => $resource
  });

  # No host-meta found
  return undef unless $domain_hm;

  if (lc $domain_hm->at('Subject')->text eq lc $resource) {

    # Return lrdd document as HostMeta resource
    return $domain_hm;
  };

  # Returns a Mojo::DOM node
  my $lrdd = $domain_hm->get_link('lrdd');

  # Get uri by using template
  my $uri;
  if ($uri = $lrdd->{template}) {
    my $res = b($resource)->url_escape;
    $uri =~ s/\{uri\}/$res/;
  }

  # Get uri by using href
  elsif (not ($uri = $lrdd->{href})) {
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
    after_fetching_lrdd => (
      $plugin,
      $c,
      $resource,
      $host,
      $lrdd_xrd, # Todo: This is no reference?
      $lrdd_xrd_doc->res
    ));

  # Retrieved document is no XRD
  return undef unless $lrdd_xrd;

  # Return lrdd document
  return $lrdd_xrd;
};


# Prepare and serve
sub _prepare_and_serve {
  my ($plugin, $c, $uri) = @_;

  my $ok = $plugin->_prepare($c, $uri);

  # If already rendered do nothing
  return if $c->res->body;

  # uri was not resolved
  return $c->render_xrd(undef, $uri) unless $ok;

  # Get local xrd document
  my $xrd = $plugin->_serve($c, $uri);

  # Serve local XRD document
  return $c->render_xrd($xrd => $uri);
};


# Prepare LRDD
sub _prepare {
  my ($plugin, $c, $uri) = @_;

  my $ok = 0;

  # Emit 'on_prepare_lrdd' hook
  $c->app->plugins->emit_hook(
    on_prepare_lrdd => (
      $plugin, $c, $uri, \$ok
    ));

  return $ok;
};


# Serve LRDD
sub _serve {
  my $plugin = shift;
  my $c = shift;
  my $uri = shift;

  # New xrd
  my $lrdd_xrd = $c->new_xrd;
  $lrdd_xrd->add('Subject' => $uri);

  # Run hook
  $c->app->plugins->emit_hook(
    before_serving_lrdd => (
      $plugin, $c, $uri, $lrdd_xrd
    ));

  return $lrdd_xrd;
};


1;


__END__

=pod

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


=head1 METHODS

=head2 C<register>

  # Mojolicious
  $app->plugin('LRDD');

  # Mojolicious::Lite
  plugin 'LRDD';

Called when registering the plugin.


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


=head1 HELPERS

=head2 C<lrdd>

  # In Controllers:
  my $xrd = $self->lrdd('https://sojolicio.us/image.gif');

Returns the LRDD L<Mojolicious::Plugin::XRD> document.


=head1 HOOKS

=over 2

=item C<before_fetching_lrdd>

  $mojo->hook(
    'before_fetching_lrdd' => sub {
      my ($plugin,
          $c,
          $resource,
          $host,
          $lrdd_xrd_ref) = @_;
      my $xrd = $c->new_xrd;
      $xrd->add('Subject => 'me');
      $$lrdd_xrd_ref = $xrd;
    });

This hook is run before a link-based resource descriptor document
is fetched. This is useful for caching. The hook passes the plugin object,
the current controller object, the resource identifier,
the host to ask for the resource, and an empty string reference,
meant to refer to the xrd_object.
If the XRD reference is filled, the fetching will not proceed.

=item C<after_fetching_lrdd>

  $mojo->hook(
    'after_fetching_lrdd' => sub {
	my ($plugin,
	    $c,
	    $resource,
	    $lrdd_xrd,
            $lrdd_response) = @_;
       print $lrdd_xrd->to_pretty_xml;
      });

This hook is run after a resource descriptor document is
retrieved. This can be used for caching.
The hook passes the plugin object, the current controller object,
the resource identifier, a string reference, meant to refer to
the XRD object, and the L<Mojo::Message::Response> object from the request.

=item C<on_prepare_lrdd>

  $mojo->hook(
    'on_prepare_lrdd' => (
      my ($plugin, $c, $resource, $ok_ref) = @_;
      if ($resource eq 'http://sojolicio.us/catz') {
        $$ok_ref = 1;
      };
  ));

This hook is run on the preparation of serving
a lrdd document. The hook passes the plugin object,
the current controller object, the identifier of the
resource and a scalar reference.
If a resource description exists for a given resource,
the scalar of the scalar reference should be set to true.
The serving process will be stopped, if content was already
rendered and not found will be rendered, if the scalar
reference is false.

=item C<before_serving_lrdd>

  $mojo->hook(
    'before_serving_lrdd' => sub {
      my ($plugin, $c, $resource, $lrdd_xrd) = @_;
      $lrdd_xrd->add_link('hcard' => { href => '/me.hcard' } );
    });

This hook is run before the XRD document is served.
The hook passes the plugin object, the current controller object,
the identifier of the resource and the XRD object.

=back

=head1 DEPENDENCIES

L<Mojolicious> (best with SSL support),
L<Mojolicious::Plugin::HostMeta>.

=head1 AVAILABILITY

  https://github.com/Akron/Sojolicious

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2011-2012, Nils Diewald.

This program is free software, you can redistribute it
and/or modify it under the same terms as Perl.

=cut
