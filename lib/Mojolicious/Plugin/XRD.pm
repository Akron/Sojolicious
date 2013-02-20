package Mojolicious::Plugin::XRD;
use Mojo::Base 'Mojolicious::Plugin';
use Mojo::Util qw/quote/;

# Register Plugin
sub register {
  my ($plugin, $mojo) = @_;

  # Add types
  for ($mojo->types) {
    $_->type(jrd => 'application/jrd+json');
    $_->type(xrd => 'application/xrd+xml');
  };

  # Add 'render_xrd' helper
  $mojo->helper(
    render_xrd => sub {
      my ($c, $xrd, $res) = @_;

      # Define xrd or jrd
      $c->stash('format' => scalar $c->param('format')) unless $c->stash('format');

      # Add CORS header
      $c->res->headers->header('Access-Control-Allow-Origin' => '*');

      my $status = 200;

      # Not found
      unless (defined $xrd) {
	$status = 404;
	$xrd = $c->new_xrd;
	$xrd->add(Subject => $res);
      }

      # rel parameter
      elsif ($c->param('rel')) {
	$xrd = $c->new_xrd($xrd->to_xml);

	# Create CSS selector for unwanted relations
	my $rel = 'Link:' . join(':', map { 'not([rel=' . quote($_) . '])'} $c->param('rel'));

	# Delete all unwanted relations
	$xrd->find($rel)->pluck('remove');
      };

      # content negotiation
      $c->respond_to(
	json => sub { $c->render(
	  status => $status,
	  data   => $xrd->to_json,
	  format => 'jrd'
	)},
	jrd => sub { $c->render(
	  status => $status,
	  data   => $xrd->to_json,
	  format => 'jrd'
	)},
	any => sub { $c->render(
	  status => $status,
	  data   => $xrd->to_pretty_xml,
	  format => 'xrd'
	)}
      );
    });

  # Add new_xrd helper
  unless (exists $mojo->renderer->helpers->{'new_xrd'}) {
    $mojo->plugin(XML => {
      new_xrd => ['XRD']
    });
  };
};

1;

__END__

=pod

=head1 NAME

Mojolicious::Plugin::XRD - Plugin for rendering XRD documents


=head1 SYNOPSIS

  # Mojolicious
  $self->plugin('XRD');

  my $xrd = $self->new_xrd;
  $self->render_xrd($xrd);


=head1 DESCRIPTION

L<Mojolicious::Plugin::XRD> is a plugin to support
L<Extensible Resource Descriptor|http://docs.oasis-open.org/xri/xrd/v1.0/xrd-1.0.html> documents,
that where created using L<MojoX::XML::XRD>.

Additionally it supports the C<rel> parameter of the
L<WebFinger|https://datatracker.ietf.org/doc/draft-jones-appsawg-webfinger/>
Specification.

=head1 METHODS

=head2 register

  # Mojolicious
  $app->plugin('XRD');

  # Mojolicious::Lite
  plugin 'XRD';

Called when registering the plugin.


=head1 HELPERS

=head2 render_xrd

  # In Controllers
  $self->render_xrd( $xrd );
  $self->render_xrd( undef, 'acct:peter@sojolicio.us' );

The helper C<render_xrd> renders an XRD object either
in C<xml> or in C<json> notation, depending on the request.
If an XRD object is empty, it renders a 404 error
and accepts a second parameter as the subject of the 404.


=head2 new_xrd

  # In Controller:
  my $xrd = $self->new_xrd;

Returns a new L<MojoX::XML::XRD> object.

=head1 DEPENDENCIES

L<Mojolicious>,
L<MojoX::XML>,
L<Mojolicious::Plugin::XML>.


=head1 AVAILABILITY

  https://github.com/Akron/Sojolicious


=head1 COPYRIGHT AND LICENSE

Copyright (C) 2011-2013, L<Nils Diewald|http://nils-diewald.de>.

This program is free software, you can redistribute it
and/or modify it under the same terms as Perl.

=cut
