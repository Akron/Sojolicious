package Mojolicious::Plugin::XRD;
use Mojo::Base 'Mojolicious::Plugin';

# Register Plugin
sub register {
    my ($plugin, $mojo) = @_;

    # Apply XRD mime-Type
    $mojo->types->type('xrd' => 'application/xrd+xml');

    # Add 'new_xrd' helper
    $mojo->helper(
	'new_xrd' => sub {
	    shift; # Either Controller or App
	    return Mojolicious::Plugin::XRD::Document
		->new(@_);
	});

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
				  data   => $xrd->to_pretty_xml,
				  format => 'xrd'
				)}
		);
	});
};

# Document class
package Mojolicious::Plugin::XRD::Document;
use Mojo::Base 'Mojolicious::Plugin::XML::Serial';
use Mojolicious::Plugin::Date::RFC3339;

# Namespace declaration
our ($xrd_ns, $xsi_ns);
BEGIN {
    our $xrd_ns = 'http://docs.oasis-open.org/ns/xri/xrd-1.0';
    our $xsi_ns = 'http://www.w3.org/2001/XMLSchema-instance';
};

# Constructor
sub new {
    my $class = ref($_[0]) ? ref(shift(@_)) : shift;

    # Start XRD from scratch
    unless ($_[0]) {
	return $class->SUPER::new(
	    'XRD', {
		'xmlns'     => $xrd_ns,
		'xmlns:xsi' => $xsi_ns
	    });
    };
    
    # Use constructor from parent class
    $class->SUPER::new(@_);
};

# Add Property
sub add_property {
    my $self = shift;

    my %hash = (
	type => shift,
	%{ shift(@_) } 
	);

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
    my %hash = (
	rel => shift,
	%{ shift(@_) } 
	);
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
    my $dom  = $self->root;

    my %object;

    # Serialize Subject and Expires
    foreach (qw/Subject Expires/) {
	my $obj = $dom->at($_);
	$object{lc($_)} = $obj->text if $obj;
    };

    # Serialize aliases
    my @aliases;
    $dom->find('Alias')->each(
	sub {
	    push(@aliases, shift->text );
	});
    $object{'aliases'} = \@aliases if @aliases;

    # Serialize titles
    my $titles = _to_json_titles($dom);
    $object{'titles'} = $titles if keys %$titles;

    # Serialize properties
    my $properties = _to_json_properties($dom);
    $object{'properties'} = $properties if keys %$properties;

    # Serialize links
    my @links;
    $dom->find('Link')->each(
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
    $node->find('Title')->each(
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
    $node->find('Property')->each(
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

Mojolicious::Plugin::XRD

=head1 SYNOPSIS

  # Mojolicious
  $self->plugin('XRD');

  # Mojolicious::Lite
  plugin 'XRD';

=head1 DESCRIPTION

L<Mojolicious::Plugin::XRD> is a plugin to support 
Extensible Resource Descriptor (XRD) documents
(see L<Specification|http://docs.oasis-open.org/xri/xrd/v1.0/xrd-1.0.html>).

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

=head2 C<render_xrd>

  # In Controllers
  $self->render_xrd( $xrd );

The helper C<render_xrd> renders an XRD object either
in C<xml> or in C<json> notation, depending on the request.

=head1 METHODS

L<Mojolicious::Plugin::XRD::Document> inherits all methods
from L<Mojolicious::Plugin::XML::Serial> and implements the
following new ones.

=head2 C<add_property>

  my $type = $xrd->add_property('descrybedby' => { href => '/me.foaf' } );

Adds a property to the xrd document.
Returns a L<Mojolicious::Plugin::XML::Serial> object.

=head2 C<get_property>

  my $type = $xrd->get_property('type');

Returns a L<Mojo::DOM> element of the first property
elemet of the given type.

=head2 C<add_link>

  my $type = $xrd->add_link('hcard' => { href => '/me.hcard' } );

Adds a link to the xrd document.
Returns a L<Mojolicious::Plugin::XML::Serial> object.

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

L<Mojolicious::Plugin::XRD> establishes the following mime-types:

  'xrd': 'application/xrd+xml'

=head1 DEPENDENCIES

L<Mojolicious>,
L<Mojolicious::Plugin::XML::Serial>.

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2011, Nils Diewald.

This program is free software, you can redistribute it
and/or modify it under the same terms as Perl.

=cut
