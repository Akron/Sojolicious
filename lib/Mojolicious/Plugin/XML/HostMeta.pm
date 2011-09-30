package Mojolicious::Plugin::XML::HostMeta;
use Mojo::Base 'Mojolicious::Plugin::XML::Base';

our $PREFIX = 'hm';
our $NAMESPACE = 'http://host-meta.net/xrd/1.0';

sub new {  warn 'Only use as an extension to XRD'; 0; };

sub add_host { shift->add('Host', shift) };

1;


__END__

=pod

=head1 NAME

Mojolicious::Plugin::XML::HostMeta - HostMeta Format Plugin

=head1 SYNOPSIS

  # Mojolicious
  $app->plugin('XML' => {
    'new_hostmeta' => ['XRD', 'HostMeta']
  });

  # Mojolicious::Lite
  plugin 'XML' => {
    new_hostmeta => ['XRD', 'HostMeta']
  };

  # In Controllers
  my $xrd = $self->new_hostmeta;
  $xrd->add_host('sojolicio.us');
  $self->render_xml($xrd);

=head1 DESCRIPTION

L<Mojolicious::Plugin::XML::HostMeta> is an extension
for L<Mojolicious::Plugin::XML::XRD> and provides an addititional
function for the work with HostMeta files as described in
L<http://tools.ietf.org/html/draft-hammer-hostmeta|Specification>.

=head1 METHODS

=head2 C<add_host>

  $xrd->add_host('sojolicio.us');

Add host information to XRD document.

=head1 DEPENDENCIES

L<Mojolicious>,
L<Mojolicious::Plugin::XML>,
L<Mojolicious::Plugin::XML::XRD>.

=head1 AVAILABILITY

  https://github.com/Akron/Sojolicious

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2011, Nils Diewald.

This program is free software, you can redistribute it
and/or modify it under the same terms as Perl.

=cut
