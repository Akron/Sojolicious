package Mojolicious::Plugin::XML::XRD;
use Mojo::Base 'Mojolicious::Plugin::XML::Base';
use Mojolicious::Plugin::Date::RFC3339;

our $MIME      = 'application/xrd+xml';
our $NAMESPACE = 'http://docs.oasis-open.org/ns/xri/xrd-1.0';
our $PREFIX    = 'xrd';

# Todo: Allow for JRD-to-XRD Conversion

# Constructor
sub new {
  my $class = shift;

  unshift(@_, 'XRD') unless $_[0];

  my $xrd = $class->SUPER::new(@_);

  # Todo: To make this work embedded,
  #        a 'register' method is needed

  # Add XMLSchema instance namespace
  $xrd->add_namespace(
    'xsi' => 'http://www.w3.org/2001/XMLSchema-instance');

  return $xrd;
};


# Add Property
sub add_property {
  my $self = shift;
  my $type = shift;

  my %hash =
    (ref($_[0]) && ref($_[0]) eq 'HASH') ?
      %{ shift(@_) } : ();

  $hash{type} = $type;

  return $self->add('Property' => \%hash => @_ );
};


# Get Property
sub get_property {
  my $self = shift;

  return unless $_[0];

  my $type = shift;

  # Returns the first match
  return $self->at( qq{Property[type="$type"]} );
};


# Add Link
sub add_link {
  my $self = shift;
  my $rel = shift;

  my %hash =
    (ref($_[0]) && ref($_[0]) eq 'HASH') ?
      %{ shift(@_) } : ();

  $hash{rel} = $rel;

  return $self->add('Link' => \%hash => @_ );
};


# Get Link
sub get_link {
  my $self = shift;

  return unless $_[0];

  my $rel = shift;

  # Returns the first match
  return $self->at( qq{Link[rel="$rel"]} );
};


# Get expiration date as epoch
sub get_expiration {
  my $self = shift;
  my $exp = $self->at('Expires');

  return 0 unless $exp;

  return Mojolicious::Plugin::Date::RFC3339->new($exp->text)->epoch;
};


# Render JRD
sub to_json {
  my $self = shift;
  my $root  = $self->root->at(':root');

  my %object;

  # Serialize Subject and Expires
  foreach (qw/Subject Expires/) {
    my $obj = $root->at($_);
    $object{lc($_)} = $obj->text if $obj;
  };

  # Serialize aliases
  my @aliases;
  $root->children('Alias')->each(
    sub {
      push(@aliases, shift->text );
    });
  $object{'aliases'} = \@aliases if @aliases;

  # Serialize titles
  my $titles = _to_json_titles($root);
  $object{'titles'} = $titles if keys %$titles;

  # Serialize properties
  my $properties = _to_json_properties($root);
  $object{'properties'} = $properties if keys %$properties;

  # Serialize links
  my @links;
  $root->children('Link')->each(
    sub {
      my $link = shift;
      my $link_att = $link->attrs;

      my %link_prop;
      foreach (qw/rel template href/) {
	if (exists $link_att->{$_}) {
	  $link_prop{$_} = $link_att->{$_};
	};
      };

      # Serialize link titles
      my $link_titles = _to_json_titles($link);
      $link_prop{'titles'} = $link_titles if keys %$link_titles;

      # Serialize link properties
      my $link_properties = _to_json_properties($link);
      $link_prop{'properties'} = $link_properties
	if keys %$link_properties;

      push(@links, \%link_prop);
    });
  $object{'links'} = \@links if @links;
  return Mojo::JSON->new->encode(\%object);
};


# Serialize node titles
sub _to_json_titles {
  my $node = shift;
  my %titles;
  $node->children('Title')->each(
    sub {
      my $val  = $_->text;
      my $lang = $_->attrs->{'xml:lang'} || 'default';
      $titles{$lang} = $val;
    });
  return \%titles;
};


# Serialize node properties
sub _to_json_properties {
  my $node = shift;
  my %property;
  $node->children('Property')->each(
    sub {
      my $val = $_->text;
      my $type = $_->attrs->{'type'} || 'null';
      $property{$type} = $val;
    });
  return \%property;
};

1;

__END__

=pod

=head1 NAME

Mojolicious::Plugin::XML::XRD - Extensible Resource Descriptor plugin

=head1 SYNOPSIS

  # Mojolicious
  $self->plugin('XML' => sub {
    new_xrd => ['XRD']
  });
  $self->plugin('XRD');

  my $xrd = $self->new_xrd;
  $xrd->add_property('descrybedby' => { href => '/me.foaf' } );
  $self->render_xml($xrd);
  # or
  $self->render_xrd($xrd); # Mojolicious::Plugin::XRD

=head1 DESCRIPTION

L<Mojolicious::Plugin::XRD> is a plugin to support
Extensible Resource Descriptor (XRD) documents rendering
(see L<Specification|http://docs.oasis-open.org/xri/xrd/v1.0/xrd-1.0.html>),
that where created using L<Mojolicious::Plugin::XML::XRD>.

=head1 METHODS

L<Mojolicious::Plugin::XML::XRD> inherits all methods
from L<Mojolicious::Plugin::XML::Base> and implements the
following new ones.

=head2 C<add_property>

  my $type = $xrd->add_property('descrybedby' => { href => '/me.foaf' } );

Adds a property to the xrd document.
Returns a L<Mojolicious::Plugin::XML> object.

=head2 C<get_property>

  my $type = $xrd->get_property('type');

Returns a L<Mojo::DOM> element of the first property
elemet of the given type.

=head2 C<add_link>

  my $type = $xrd->add_link('hcard' => '/me.hcard');
  my $type = $xrd->add_link('hcard' => { href => '/me.hcard' });

Adds a link to the xrd document.
Returns a L<Mojolicious::Plugin::XML::XRD> object.

=head2 C<get_link>

  my $link = $xrd->get_link('rel');

Returns a L<Mojo::DOM> element of the first link
element of the given relation.

=head2 C<get_expiration>

  my $epoch = $xrd->get_expiration;

Returns the expiration date of the document as 
a UNIX epoch value.
This may differ to the HTTP expiration date.

=head2 C<to_json>

  my $jrd = $xrd->to_json;

Returns a JSON string representing a JRD document.

=head1 MIME-TYPES

When loaded as a base class, L<Mojolicious::Plugin::XML::XRD>
establishes the following mime-type:

  'xrd': 'application/xrd+xml'

=head1 DEPENDENCIES

L<Mojolicious>,
L<Mojolicious::Plugin::XML>,
L<Mojolicious::Plugin::Date::RFC3339>.

=head1 AVAILABILITY

  https://github.com/Akron/Sojolicious

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2011, Nils Diewald.

This program is free software, you can redistribute it
and/or modify it under the same terms as Perl.

=cut

