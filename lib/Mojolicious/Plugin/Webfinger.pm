package Mojolicious::Plugin::Webfinger;
use Mojo::Base 'Mojolicious::Plugin';
use Mojo::ByteStream 'b';

# Register Plugin
sub register {
  my ($plugin, $mojo, $param) = @_;

  # Load LRDD if not already loaded.
  # This automatically loads the Hostmeta, XRD and Endpoints plugins.
  unless (exists $mojo->renderer->helpers->{'lrdd'}) {
    $mojo->plugin('LRDD');
  };

  # Add 'webfinger' helper
  $mojo->helper(
    'webfinger' => sub {
      my $c = shift;
      my ($user, $domain, $norm) = $c->parse_acct( shift );

      # If local, serve local
      if ($domain ~~ [$c->req->url->host, 'localhost']) {
	return $plugin->_serve_webfinger($c, $norm);
      };
      return $c->lrdd($norm => $domain);
    });

  # Add 'parse_acct' helper
  $mojo->helper(
    'parse_acct' => sub {
      my ($c, $acct) = @_;

      # Delete scheme if exists
      $acct =~ s/^acct://i;

      return unless $acct;

      # Split user from domain
      my ($user, $domain) = split('@', lc $acct);

      # Acct is not valid
      return if !$user || $user =~ /[^-_\w]/;

      # Use request host if no host is given
      $domain ||= $c->req->url->host || 'localhost';

      # Create norm writing
      my $norm = 'acct:' . $user . '@' . $domain;

      return ($user, $domain, $norm) if wantarray;
      return $norm;
    });

  # on prepare webfinger hook
  $mojo->hook(
    'on_prepare_lrdd' => sub {
      my ($lrdd_plugin, $c, $uri, $ok_ref) = @_;

      my ($user, $domain, $norm);
      if (!$$ok_ref && ($uri = $c->parse_acct($uri))) {

	# Emit 'on_prepare_webfinger' hook
	$mojo->plugins->emit_hook(
	  'on_prepare_webfinger' => (
	    $plugin, $c, $uri, $ok_ref
	  ));

	if ($$ok_ref) {
	  # Get local xrd document
	  my $xrd = $plugin->_serve_webfinger($c, $uri);

	  # Serve local XRD document
	  $c->render_xrd($xrd) if $xrd;
	};
      };
      return;
    }
  );
};


# Serve webfinger
sub _serve_webfinger {
  my $plugin = shift;
  my $c      = shift;

  # Parse acct (normally not necessary, as it is norm)
  my ($user, $domain, $norm) = $c->parse_acct( shift );

  # Get local account data
  if (!$domain ||
      $domain ~~ [$c->req->url->host, 'localhost']) {

    my $wf_xrd = $c->new_xrd;
    $wf_xrd->add('Subject' => $norm);

    # Run hook
    $c->app->plugins->emit_hook(
      'before_serving_webfinger' => (
	$plugin, $c, $norm, $wf_xrd
      ));

    # Return webfinger document
    return $wf_xrd;
  };

  return undef;
};

1;

__END__

=head1 NAME

Mojolicious::Plugin::Webfinger - Webfinger Plugin

=head1 SYNOPSIS

  # Mojolicious
  $app->plugin('Webfinger');

  my $r = $app->routes;
  $r->route('/webfinger/:uri')->lrdd;

  my $profile_page =
    $c->webfinger('acct:bob@example.org')
        ->get_link('describedby')
        ->attrs->{'href'};

  # Mojolicious::Lite
  plugin 'Webfinger';
  (any '/webfinger')->lrdd;

=head1 DESCRIPTION

L<Mojolicious::Plugin::Webfinger> provides several functions for
the Webfinger Protocol (see L<http://code.google.com/p/webfinger/wiki/WebFingerProtocol|Specification>).
It hooks into link-based descriptor discovery as provided by
L<Mojolicious::Plugin::LRDD>.

=head1 HELPERS

=head2 C<webfinger>

  # In Controllers:
  my $xrd = $self->webfinger('me');
  my $xrd = $self->webfinger('acct:me@sojolicio.us');

Returns the Webfinger L<Mojolicious::Plugin::XRD> document.

=head2 C<parse_acct>

  # In Controllers:
  my ($user, $domain, $norm) =
      $self->parse_acct('acct:me@sojolicious');
  my $norm = $self->parse_acct('me');

Returns the user, the domain part of an acct scheme and
the normative writing. It accepts short writings like 'acct:me'
and 'me' as well as full acct writings.
In a string context, it returns the normative writing.

=head1 HOOKS

In this plugin, Webfinger is treated as a special case
of link-based ressource descriptor discovery. Please refer
to L<Mojolicious::Plugin::LRDD> for further hooks
regarding discovery.

=item C<on_prepare_webfinger>

  $mojo->hook(
    'on_prepare_webfinger' => sub {
      my ($plugin, $c, $acct, $ok_ref) = @_;
      if ($uri eq 'akron@sojolicio.us') {
        $$ok_ref = 1;
      };
    });

This hook is run before a webfinger document is served.
The hook passes the plugin object, the current controller object,
the acct ressource and a scalar reference.
If a ressource description exists for a given acct name,
the scalar of the scalar reference should be set to true.

=item C<before_serving_webfinger>

  $mojo->hook(
    'before_serving_webfinger' => sub {
      my ($plugin, $c, $acct, $wf_xrd) = @_;
      $wf_xrd->add_link('hcard' => { href => '/me.hcard' } );
    });

This hook is run before the XRD document is served.
The hook passes the plugin object, the current controller object,
the acct name and the XRD object.

=back

=head1 DEPENDENCIES

L<Mojolicious> (best with SSL support),
L<Mojolicious::Plugin::LRDD>.

=head1 AVAILABILITY

  https://github.com/Akron/Sojolicious

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2011, Nils Diewald.

This program is free software, you can redistribute it
and/or modify it under the same terms as Perl.

=cut
