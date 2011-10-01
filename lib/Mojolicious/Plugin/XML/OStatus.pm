package Mojolicious::Plugin::XML::OStatus;
use Mojo::Base 'Mojolicious::Plugin::XML::Base';

our $PREFIX    = 'ostatus';
our $NAMESPACE = 'http://ostatus.org/schema/1.0/';

# Only use as an extension
sub new {
  warn 'Only use as an extension to Atom';
  0;
};


# Add 'attention' link
sub add_attention {
  shift->add_link(
    rel => $PREFIX . ':attention',
    href => shift, @_
  );
};


# Add 'conversation' link
sub add_conversation {
  shift->add_link(
    rel => $PREFIX . ':conversation',
    href => shift, @_
  );
};

1;

__END__

=pod

=head1 NAME

Mojolicious::Plugin::XML::OStatus - OStatus (Atom) Format Plugin

=head1 SYNOPSIS

  # Mojolicious
  $app->plugin('XML' => {
    'new_ostatus' => ['Atom', (...), 'Ostatus']
  });

  # Mojolicious::Lite
  plugin 'XML' => {
    new_ostatus => ['Atom', (...), 'OStatus']
  };

  # In Controllers
  my $feed = $self->new_ostatus('feed');
  my $entry = $feed->add_entry;
  $entry->add_author(name => 'Akron');
  $entry->add_attention('http://sojolicio.us/user/peter');
  $entry->add_conversation('http://sojolicio.us/conv/34');
  $self->render_xml($entry);

=head1 DESCRIPTION

L<Mojolicious::Plugin::XML::OStatus> is an extension
for L<Mojolicious::Plugin::XML::Atom> and provides several functions
for the work with OStatus as described in
L<http://ostatus.org/sites/default/files/ostatus-1.0-draft-2-specification.html|Specification>.

=head1 METHODS

L<Mojolicious::Plugin::XML::OStatus> inherits all methods
from L<Mojolicious::Plugin::XML> and implements the
following new ones.

=head2 C<add_attention>

  $entry->add_attention('http://sojolicio.us/user/peter');

Add attention link to the Atom document.

=head2 C<add_conversation>

  $entry->add_conversation('http://sojolicio.us/conv/34');

Add conversation link to the Atom document.

=head1 DEPENDENCIES

L<Mojolicious>,
L<Mojolicious::Plugin::XML>,
L<Mojolicious::Plugin::XML::Atom>,
L<Mojolicious::Plugin::Date::RFC3339>.

=head1 AVAILABILITY

  https://github.com/Akron/Sojolicious

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2011, Nils Diewald.

This program is free software, you can redistribute it
and/or modify it under the same terms as Perl.

=cut
