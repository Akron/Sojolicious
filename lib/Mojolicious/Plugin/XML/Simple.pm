package Mojolicious::Plugin::XML::Simple;
use strict;
use warnings;
use Mojo::Base -base;
use Mojo::Util qw/xml_escape quote/;
use Scalar::Util qw( weaken );
use Mojo::DOM;
has 'tree';

# Indentation for pretty printing
our $indent;
BEGIN {
    $indent = '  ';
};

# Constructor
sub new {
    my $class = shift;
    my $doc = shift;

    # No document given
    if (!$doc) {
	$doc = [
	    'root',
	    [ 'pi', 'xml version="1.0"'.
	            ' encoding="UTF-8"'.
	            ' standalone="yes"' ],
	    [ 'tag',
	      'xml',
	      {}
	    ]];
    };

    # Document given as tree
    if ( ref( $doc ) ) {
	$doc->[2]->[3] = $doc;
    }

    # Document given as string
    elsif ($doc) {

	# Parse document
	my $dom = Mojo::DOM->new(xml => 1);
	$doc =~ s/>[\s\r\n]+</></g;
	$dom->parse($doc);
	$doc = $dom->tree;
    };

    return bless( { tree => $doc }, $class);
};

sub new_node {
    my $class = ref($_[0]) =~ /::/ ? ref(shift) : shift;

    my $parent = shift;

    my $type = shift;

    my $attr = ref($_[0]) eq 'HASH' ? shift : {};
    my ($content,
	$comment) = @_;

    for ($content, $comment) {
	xml_escape($_) if $_;
    };

    my $self = [];
    $comment ||= '';

    push(@$self, [ 'comment', $comment ]) if $comment;

    my $tag = [ 'tag',
	        $type,
	        $attr,
	        $parent ];

    push(@$tag, [ 'text', $content ]) if $content;

    push(@$self, $tag);

    return bless( { tree => $self }, $class);
};

# Appends a new node to the XML Node
sub add {
    my $self = shift;
    my $tree = $self->tree;

    my $parent = ($tree->[0] eq 'root') ? $tree->[2] : $tree->[0];

    weaken($parent);

    my $node = $self->new_node($parent, @_);

    if ($tree->[$#$tree]->[0] eq 'tag') {
	push( @{ $tree->[ $#{ $tree } ] }, @{ $node->tree });
    } else {
	push( @{ $parent }, @{ $node->tree });
    };

    return $node;
};

# Prepends a Comment to the XML node
sub comment {
    my $self = shift;
    my $tree = $self->tree;

    my $comment = shift;

    if ($tree->[0] eq 'root') {
	return;
    };

    my $offset = 4;
    my $parent = $tree->[0]->[3];

    foreach my $e ( @{ $parent }[ $offset .. $#{ $parent } ]) {

	$offset++;
	if ($e eq $tree->[0]) {
	    last;
	};
    };

    my $pos_e = $parent->[ $offset - 2 ];

    xml_escape( $comment );

    if ($pos_e->[0] &&
	$pos_e->[0] eq 'comment') {
	$pos_e->[1] .= '; ' . $comment;
    }

    else {
	splice(@$parent,
	       $offset - 1,
	       0,
	       [ 'comment', $comment ]);
    };

    return $self;
};

sub to_xml {
    my $self = shift;
    return _render(0, $self->tree);
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

# Return Mojo::DOM
sub dom {
    my $self = shift;

    if ($self->{dom}) {
	return $self->{dom};
    };

    my $dom = Mojo::DOM->new( xml => 1 );
    $dom->tree( $self->tree );
    $self->{dom} = $dom;
    return $dom;

};

sub DESTROY {
    my $t = shift->tree;
    if ($t->[0] eq 'root') {
	$t->[2]->[3] = undef;
    };
};

1;

__END__

=pod

=head1 NAME

Mojolicious::Plugin::XML::Simple

=head1 SYNOPSIS

  # Mojolicious
  $self->plugin('x_r_d');

  # Mojolicious::Lite
  plugin 'x_r_d';

=head1 METHODS

L<Mojolicious::Plugin::XML::Simple> inherits all methods from
L<Mojo::Base> and implements the following new ones.

=head2 C<new>

  my $xml = Mojolicious::Plugin::XML::Simple->new(<<'EOF');


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

=head2 C<dom>

  print $xrd->dom->at('Link[rel=lrrd]')->text;

Returns the L<Mojo::DOM> representation of the object,
allowing for fine grained CSS3 selections.

=head2 C<to_xml>

  print $xrd->to_xml;

Returns a stringified XML document. This is not identical
to L<Mojo::DOM>s C<to_xml> as it applies for pretty printing.

=head1 DEPENDENCIES

L<Mojolicious>.

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2011, Nils Diewald.

This program is free software, you can redistribute it
and/or modify it under the same terms as Perl.

=cut
