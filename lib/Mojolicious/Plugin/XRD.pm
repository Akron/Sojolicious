package Mojolicious::Plugin::XRD;
use strict;
use warnings;
use Mojo::Base 'Mojolicious::Plugin';

# Register Plugin
sub register {
    my ($plugin, $mojo) = @_;

    # Apply XRD mime-Type
    $mojo->types->type('xrd' => 'application/xrd+xml');

    $mojo->helper(
	'new_xrd' => sub {
	    shift; # Either Controller or App
	    return Mojolicious::Plugin::XRD::Document
		->new(@_);
	}
	);

};

package Mojolicious::Plugin::XRD::Document;
use Mojo::Base 'Mojolicious::Plugin::XML::Simple';
use strict;
use warnings;

our ($xrd_ns, $xsi_ns);
BEGIN {
    our $xrd_ns = 'http://docs.oasis-open.org/ns/xri/xrd-1.0';
    our $xsi_ns = 'http://www.w3.org/2001/XMLSchema-instance';
};

# Constructor
sub new {
    my $class = ref($_[0]) ? ref(shift(@_)) : shift;

    my $document = shift;
    my $object;
    if (!$document) {
	$document = [
	    'root',
	    [ 'pi', 'xml version="1.0"'.
	            ' encoding="UTF-8"'.
	            ' standalone="yes"' ],
	    [ 'tag',
	      'XRD',
	      {
		  'xmlns' => $xrd_ns,
		  'xmlns:xsi' => $xsi_ns
	      }
	    ]
	    ];
    };
    
    return $class->SUPER::new($document);
};

# Render JRD
# sub to_json {};

# Get root Property
sub get_property {
    my $self = shift;
    my $type = shift;

    # Returns the first match
    return $self->dom->at( qq{Property[type="$type"]} );
};

# Get Link
sub get_link {
    my $self = shift;
    my $rel = shift;

    # Returns the first match
    return $self->dom->at( qq{Link[rel="$rel"]} );
};

1;

__END__

=pod

=head1 NAME

Mojolicious::Plugin::XRD

=head1 SYNOPSIS

  # Mojolicious
  $self->plugin('x_r_d');

  # Mojolicious::Lite
  plugin 'x_r_d';

=head1 DESCRIPTION

L<Mojolicious::Plugin::XRD> is a plugin to support 
Extensible Resource Descriptor (XRD) documents
(see L<http://docs.oasis-open.org/xri/xrd/v1.0/xrd-1.0.html|Specification>).

=head1 HELPERS

=head2 C<new_xrd>

  my $xrd = $self->new_xrd;

  my $xrd = $self->new_xrd(<<'XRD');
  <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
  <XRD xmlns="http://docs.oasis-open.org/ns/xri/xrd-1.0"
       xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
    <!-- Foobar Link! -->
    <Link rel="foo">bar</Link>
  </XRD>
  XRD

The helper C<new_xrd> returns an XRD object.

=head1 METHODS

=head2 C<add>

  my $xrd_node = $xrd->add('Link', { rel => 'lrdd' });

Appends a new Element to the XRDs root and returns a
C<Mojolicious::Plugin::XRD::Node> object.

The C<Mojolicious::Plugin::XRD::Node> object has following methods.

=head3 C<add>

  $xrd_node_inner = $xrd_node->add('Title', 'Webfinger');

Appends a new Element to the XRD node.

=head3 C<comments>

  $xrd_node = $xrd_node->comment('Resource Descriptor');

Prepends a comment to the XRD node.

=head2 C<get_property>

  my $type = $xrd->get_property('type');

Returns a L<Mojo::DOM> element of the first property
elemet of the given type.

=head2 C<get_link>

  my $link = $xrd->get_link('rel');

Returns a L<Mojo::DOM> element of the first link
element of the given relation.
  
=head2 C<dom>

  print $xrd->dom->at('Link[rel=lrrd]')->text;

Returns the L<Mojo::DOM> representation of the object,
allowing for fine grained CSS3 selections.

=head2 C<to_xml>

  print $xrd->to_xml;

Returns a stringified XML document. This is not identical
to L<Mojo::DOM>s C<to_xml> as it applies for pretty printing.

=head1 MIME-TYPES

L<Mojolicious::Plugin::XRD> establishes the following mime-types:

  'xrd': 'application/xrd+xml'

=head1 DEPENDENCIES

L<Mojolicious>.

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2011, Nils Diewald.

This program is free software, you can redistribute it
and/or modify it under the same terms as Perl.

=cut
