package Mojolicious::Plugin::XRD;
use Mojo::Base 'Mojolicious::Plugin';

our $DELEGATE = 'Mojolicious::Plugin::XML::XRD';

# Register Plugin
sub register {
  my ($plugin, $mojo) = @_;

  # Add 'render_xrd' helper
  $mojo->helper(
    'render_xrd' => sub {
      my ($c, $xrd) = @_;

      $c->stash('format' => $c->param('format')) unless $c->stash('format');

      # content negotiation
      $c->respond_to(
	json => sub { $c->render(
	  data   => $xrd->to_json,
	  format => 'json'
	)},
	any  => sub { $c->render(
	  data   => $xrd->to_xml,
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

Copyright (C) 2011, Nils Diewald.

This program is free software, you can redistribute it
and/or modify it under the same terms as Perl.

=cut
