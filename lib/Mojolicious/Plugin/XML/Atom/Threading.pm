package Mojolicious::Plugin::XML::Atom::Threading;
use Mojo::Base 'Mojolicious::Plugin::XML::Base';

our $PREFIX    = 'thr';
our $NAMESPACE = 'http://purl.org/syndication/thread/1.0';
our $MIME      = 'application/atom+xml';

sub new {  warn 'Only use as an extension to Atom'; 0; };

# Add 'in-reply-to' element
sub add_in_reply_to {
  my ($self,
      $ref,
      $param) = @_;

  # No ref defined
  return unless defined $ref;

  # Adding a related link as advised in the spec
  if (defined $param->{href}) {
    $self->add_link($param->{href});
  };

  $param->{ref} = $ref;
  return $self->add('in-reply-to' => $param );
};


# Add 'link' element for replies
sub add_replies_link {
  my $self = shift;
  my $href = shift;

  # No href defined
  return unless $href;

  my %param = %{ shift(@_) };

  my %new_param = (href => $href);
  if (exists $param{count}) {
    $new_param{$PREFIX . ':count'} = delete $param{count};
  };

  if (exists $param{updated}) {
    my $date = delete $param{updated};
    unless (ref($date)) {
      $date = $self->new_date($date);
    };
    $new_param{$PREFIX . ':updated'} = $date->to_string;
  };

  unless (exists $param{type}) {
    $new_param{type} = $MIME;
  };

  # Needs atom as parent
  $self->add_link(rel => 'replies',  %new_param );
};


# Add total value
sub add_total {
  my ($self,
      $count,
      $param) = @_;

  return unless $count;

  $param ||= {};

  return $self->add('total' => $param => $count);
};

1;

__END__

=pod

=head1 NAME

Mojolicious::Plugin::XML::Atom::Threading - Threading Extension for Atom

=head1 SYNOPSIS

  use Mojolicious::Plugin::Atom;

  my $entry = Mojolicious::Plugin::XML::Atom->new('entry');
  for ($entry) {
    $_->add_extension('Mojolicious::Plugin::XML::Atom::Threading');
    $_->add_author(name => 'Zoidberg');
    $_->add_id('http://sojolicio.us/blog/2');
    $_->add_in_reply_to( 'http://sojolicio.us/blog/1',
                          { href => 'http://sojolicio.us/blog/1'});
  };
  print $entry->to_xml;

  # <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
  # <entry xmlns="http://www.w3.org/2005/Atom"
  #        xmlns:thr="http://purl.org/syndication/thread/1.0">
  #   <author>
  #     <name>Zoidberg</name>
  #   </author>
  #   <id>http://sojolicio.us/blog/2</id>
  #   <link rel="related"
  #         href="http://sojolicio.us/blog/1" />
  #   <thr:in-reply-to ref="http://sojolicio.us/blog/1"
  #                    href="http://sojolicio.us/blog/1" />
  # </entry>

=head1 DESCRIPTION

L<Mojolicious::Plugin::Atom::XML::Threading> is an extension to
L<Mojolicious::Plugin::XML::Atom> and introduces
additional functions to work for Threading as described in
L<https://www.ietf.org/rfc/rfc4685.txt|RFC4685>.

=head2 C<add_in_reply_to>

  $self->add_in_reply_to( 'http://sojolicio.us/entry/1',
                          { href => 'http://sojolicio.us/entry/1.html });

Add an C<in-reply-to> element to the Atom object.
Will automatically introduce a 'related' link, if a C<href> parameter is given.
Needs one parameter with the reference string and an optional hash with
further attributes.

=head2 C<add_replies_link>

  $self->add_replies_link( 'http://sojolicio.us/entry/1/replies',
                           { count => 5,
                             updated => $self->new_date });

Add a C<link> element with a relation of 'replies' to the atom object.
Accepts optional parameters for reply count and update.
The update accepts an L<Mojolicious::Plugin::Date::RFC3339> object.

=head2 C<add_total>

  $self->add_total(5);

Add a C<total> element for response count to the atom object.

=head1 DEPENDENCIES

L<Mojolicious>,
L<Mojolicious::Plugin::XML::Base>,
L<Mojolicious::Plugin::XML::Atom>,
L<Mojolicious::Plugin::Date::RFC3339>.

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2011, Nils Diewald.

This program is free software, you can redistribute it
and/or modify it under the same terms as Perl.

=cut
