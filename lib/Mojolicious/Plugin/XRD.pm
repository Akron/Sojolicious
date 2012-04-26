package Mojolicious::Plugin::XRD;
use Mojo::Base 'Mojolicious::Plugin';
use Mojo::Util qw/quote/;

our $DELEGATE = 'Mojolicious::Plugin::XML::XRD';

# Register Plugin
sub register {
  my ($plugin, $mojo) = @_;

  $mojo->types->type(jrd => 'application/json');

  # Add 'render_xrd' helper
  $mojo->helper(
    render_xrd => sub {
      my ($c, $xrd) = @_;

      $c->stash('format' => $c->param('format')) unless $c->stash('format');

      # rel parameter
      if ($c->param('rel')) {
	$xrd = $c->new_xrd($xrd->to_xml);
	my @rel = split(/\s+/, $c->param('rel'));
	my $rel = 'Link:' . join(':', map { 'not([rel=' . quote ($_) . '])'} @rel);
	$xrd->find($rel)->each(sub{ $_->replace('') });
      };

      # Add CORS header
      $c->res->headers->header('Access-Control-Allow-Origin' => '*');

      # content negotiation
      $c->respond_to(
	json => sub { $c->render(
	  data   => $xrd->to_json,
	  format => 'jrd'
	)},
	jrd => sub { $c->render(
	  data   => $xrd->to_json,
	  format => 'jrd'
	)},
	any  => sub { $c->render(
	  data   => $xrd->to_pretty_xml,
	  format => 'xrd'
	)}
      );
    });

  unless (exists $mojo->renderer->helpers->{'new_xrd'}) {
    $mojo->plugin('XML' => {
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
Extensible Resource Descriptor (XRD) documents
(see L<Specification|http://docs.oasis-open.org/xri/xrd/v1.0/xrd-1.0.html>),
that where created using L<Mojolicious::Plugin::XML::XRD>.
Additionally it supports the "rel" parameter of the
L<WebFinger|https://datatracker.ietf.org/doc/draft-jones-appsawg-webfinger/>
Specification.

=head1 HELPERS

=head2 C<render_xrd>

  # In Controllers
  $self->render_xrd( $xrd );

The helper C<render_xrd> renders an XRD object either
in C<xml> or in C<json> notation, depending on the request.

=head2 C<new_hostmeta>

  # In Controller:
  my $xrd = $self->new_xrd;

The helper C<new_xrd> returns a new L<Mojolicious::Plugin::XML::XRD>
object.

=head1 DEPENDENCIES

L<Mojolicious>,
L<Mojolicious::Plugin::XML>.

=head1 AVAILABILITY

  https://github.com/Akron/Sojolicious

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2011-2012, Nils Diewald.

This program is free software, you can redistribute it
and/or modify it under the same terms as Perl.

=cut
