package Mojolicious::Plugin::XRD;
use strict;
use warnings;
use Mojo::Base 'Mojolicious::Plugin';

# Register Plugin
sub register {
    my ($plugin, $mojo) = @_;

    # Apply XRD MIMe-Type
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
use strict;
use warnings;
use Mojo::Base -base;
use Mojo::DOM;
use Mojo::Util qw/xml_escape quote/;

has 'tree';
has 'url_for' => '';

our ($indent, $xrd_ns, $xsi_ns);
BEGIN {
    our $indent = '  ';
    our $xrd_ns = 'http://docs.oasis-open.org/ns/xri/xrd-1.0';
    our $xsi_ns = 'http://www.w3.org/2001/XMLSchema-instance';
};

# Constructor
sub new {
    my $class = ref($_[0]) ? ref(shift(@_)) : shift;

    my $document = shift;

    my ($xrd, $tree);

    my %self;

    if ($document) {

	# Parse document
	my $dom = Mojo::DOM->new(xml => 1);
	$dom->parse($document);
	$tree = $dom->tree;
	$xrd  = $dom->at('XRD');

	# The document is no XRD
	if (!$xrd || $xrd->namespace ne $xrd_ns) {
	    return undef;
	};

	$self{dom} = $dom;
	$xrd = $xrd->tree;

    } else {

	# Create new XRD dom
	$tree = [
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
	
	# Parent
	$tree->[2]->[3] = $tree;
	
	# XRD element
	$xrd = $tree->[2];
    };

    $self{tree} = $tree;
    $self{xrd}  = $xrd;

    # Return XRD object
    return  bless \%self, $class;
};

# Returns the Mojo::DOM representation of the document.
sub dom {
    my $self = shift;

    unless (exists $self->{dom}) {
	my $dom = Mojo::DOM->new(xml => 1);
	$dom->tree($self->{'tree'});
	$self->{dom} = $dom;
    };

    return $self->{dom};
};

# Render XRD
sub to_xml {
    my $self = shift;
    return _render(0, $self->{tree});
};

# Render JRD
# sub to_json {};

# Appends a new node to the XRD
sub add {
    my $self = shift;

    my $node = Mojolicious::Plugin::XRD::Node->new(
	$self->{xrd}, @_);

    push(@{$self->{xrd}}, @{$node});

    return $node;
};

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


# render subtrees with pretty printing
sub _render {
    my $i = shift;
    my $tree = shift;

    my $e = $tree->[0];

    if ($e eq 'tag') {
	my $subtree = 
	    [
	     @{$tree}[0..2],
	     [
	      @{$tree}[4..$#$tree]
	     ]
	    ];

	return _element($i, $subtree);

    } elsif ($e eq 'text') {

	my $escaped = $tree->[1];

	for ($escaped) {
	    next unless $_;
	    s/[\s\n]+$//;
	    s/^[\s\n]+//;
	    xml_escape($_);
	};
	return $escaped;
    }
    
    elsif ($e eq 'comment') {
	my $comment = join("\n     ".($indent x $i),
			   split('; ',$tree->[1]));
	return "\n".($indent x $i).'<!-- '.$comment." -->\n";
    }
    
    elsif ($e eq 'pi') {
	return ($indent x $i).'<?' . $tree->[1] . "?>\n";

    } elsif ($e eq 'root') {

	my $content;
	
	foreach my $child_e_i (1 .. $#$tree) {
	    $content .= _render(
		$i,
		$tree->[$child_e_i]
		);
	};

	return $content;
    };
};

# render element with pretty printing
sub _element ($$) {
    my $i = shift;
    
    my ($type,
	$qname,
	$attr,
	$child) = @{$_[0]};

    # Is the qname valid?
    warn $qname.' is no valid QName'
	unless $qname =~ /^(?:[a-zA-Z_]+:)?[^\s]+$/;

    # Start start tag
    my $content = ($indent x $i).'<'.$qname;

    # Add attributes
    $content .= _attr(($indent x $i).(' ' x (length($qname) + 2)), $attr);

    # Has the element a child?
    if ($child->[0]) {

	# Close start tag
	$content .= '>';

	# There is only a textual child - no indentation
	if (!$child->[1] &&
	    ($child->[0] && $child->[0]->[0] eq 'text')
	    ) {

	    $content .= $child->[0]->[1];
	}

	# There are some childs
	else {
	    $content .= "\n";

	    # Loop through all child elements
	    foreach my $child_e (@$child) {

		# Render next element
		$content .= _render($i+1, $child_e);
	    };

	    # Correct Indent
	    $content .= ($indent x $i);

	};

	# End Tag
	$content .= '</' . $qname . ">\n";
    }

    # No child - close start element as empty tag
    else {
	$content .= " />\n";
    };

    # return content
    return $content;
}

# render attributes with pretty printing
sub _attr ($$) {
    my $indent_space = shift;
    my %attr = %{$_[0]};

    # prepare attribute values
    foreach (values %attr) {
	xml_escape($_);
	quote($_);
    };

    # return indented attribute string
    return 
	' '. 
	join("\n".$indent_space,
	     map($_.'='.$attr{$_},
		 keys(%attr))) if keys %attr;

    # return nothing
    return '';
};

package Mojolicious::Plugin::XRD::Node;
use strict;
use warnings;

sub new {
    my $class = shift;
    my $parent = shift;

    my $type = shift;
    my $attr = ref($_[0]) eq 'HASH' ? shift : {};
    my ($content,
	$comment) = @_;

    my $self = [];
    $comment ||= '';

    push(@$self, [ 'comment', $comment ]) if $comment;

    my $tag = [ 'tag',
	        $type,
	        $attr,
	        $parent ];

    push(@$tag, [ 'text', $content ]) if $content;

    push(@$self, $tag);

    return bless($self, $class);
};

# Appends a new node to the XRD Node
sub add {
    my $self = shift;
    my $node = Mojolicious::Plugin::XRD::Node->new($self->[0], @_);

    push(@{$self->[$#$self]},@{$node});

    return $node;
};

# Prepends a Comment to the XRD node
sub comment {
    my $self = shift;
    my $comment = shift;
    my $parent = $self->[0]->[3];

    my $offset = 4;
    foreach my $e (@{$parent}[$offset .. $#{$parent}]) {
	if ($e eq $self) {
	    last;
	};
	$offset++;
    };

    my $pos_e = $parent->[$offset - 2];

    if ($pos_e->[0] &&
	$pos_e->[0] eq 'comment') {
	$pos_e->[1] .= '; '.$comment;
    }

    else {
	splice(@$parent,
	       $offset - 1,
	       0,
	       [ 'comment', $comment ]);
    };

    return $self;
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
