package Mojolicious::Plugin::XML::GeoRSS;
use Mojo::Base 'Mojolicious::Plugin::XML::Base';

our $PREFIX    = 'georss';
our $NAMESPACE = 'http://www.georss.org/georss';

sub new {  warn 'Only use as an extension'; 0; };

# Add 'point' element
sub add_geo_point ($$) {
  my $self = shift;

  # Parameterlist has wrong length
  return unless @_ == 2;

  return $self->add('point', shift . ' ' . shift);
};


# Add 'line' element
sub add_geo_line {
  my $self = shift;

  # Parameterlist not even or too small
  return if @_ % 2 || @_ < 4;
  return $self->add('line', join(' ',@_) );
};


# Add 'polygon' element
sub add_geo_polygon {
  my $self = shift;

  # Parameterlist not even or too small
  return if @_ % 2 || @_ < 6;

  # Last pair is not identical to first pair
  if ($_[0] != $_[$#_ - 1] && $_[1] != $_[$#_]) {
    push(@_, @_[0..1]);
  };
  return $self->add('polygon', join(' ',@_));
};


# Add 'box' element
sub add_geo_box ($$$$) {
  my $self = shift;

  # Parameterlist has wrong length
  return unless @_ == 4;

  return $self->add('box', join(' ',@_));
};


# Add 'circle' element
sub add_geo_circle ($$$) {
  my $self = shift;

  # Parameterlist has wrong length
  return unless @_ == 3;

  return $self->add('circle', join(' ',@_));
};


# Add properties
sub add_geo_property {
  my $self = shift;
  my %properties = @_;

  # Add all available properties
  foreach my $tag (grep(/^(?:(?:relationship|featureType)Tag|featureName)$/,
		keys %properties)) {

    my $val = $properties{$tag};

    # Add as an array, if it is one
    foreach (ref $val ? @$val : ($val)) {
      $self->add($tag, $_);
    };
  };

  return $self;
};


# Add 'floor' element
sub add_geo_floor {
  shift->add('floor', shift);
};


# Add 'even' element
sub add_geo_even {
  shift->add('even', shift);
};


# Add 'radius' element
sub add_geo_radius {
  shift->add('radius', shift);
};


# Add 'where' element
sub add_geo_where {
  shift->add('where');
};

1;

__END__

=pod

=head1 NAME

Mojolicious::Plugin::XML::GeoRSS - GeoRSS (Simple) Format Plugin

=head1 SYNOPSIS

  # Mojolicious
  $app->plugin('XML' => {
    'new_geo' => ['Atom', 'GeoRSS']
  });

  # Mojolicious::Lite
  plugin 'XML' => {
    new_geo => ['Atom', 'GeoRSS']
  };

  # In Controllers
  my $geo = $self->new_geo;
  $geo->add_geo_point(14, 5.67);
  $self->render_xml($geo);

=head1 DESCRIPTION

L<Mojolicious::Plugin::XML::GeoRSS> is an extension
for L<Mojolicious::Plugin::XML> base classes and provides addititional
functions for the work with geographic location as described in
L<http://georss.org/simple|Specification>.
This represents the simple variant rather than the GML flavour.

=head1 METHODS

=head2 C<add_geo_where>
=head2 C<add_geo_point>
=head2 C<add_geo_line>
=head2 C<add_geo_polygon>
=head2 C<add_geo_box>
=head2 C<add_geo_circle>
=head2 C<add_geo_property>
=head2 C<add_geo_floor>
=head2 C<add_geo_even>
=head2 C<add_geo_radius>

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
