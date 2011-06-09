package Mojolicious::Plugin::XML::Simple;
use strict;
use warnings;
use Mojo::Util qw/xml_escape quote/;
use Scalar::Util qw( weaken );
use Mojo::DOM;

our $indent;
BEGIN {
    $indent = '  ';
};

# Todo: Irgendwo speichern, dass es sich schon um ein DOM handelt etc.

sub new {
    my $class = shift;
    my $doc = shift;

    if (ref($doc)) {
	weaken($doc);
	$doc->[2]->[3] = $doc;

    } else {

	# Parse document
	my $dom = Mojo::DOM->new(xml => 1);
	$doc =~ s/>[\s\r\n]+</></g;
	$dom->parse($doc);
	$doc = $dom->tree;
    };

    return bless($doc, $class);
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

    return bless($self, $class);
};

# Appends a new node to the XML Node
sub add {
    my $self = shift;

    my $parent = ($self->[0] eq 'root') ? $self->[2] : $self->[0];

    weaken($parent);

    my $node = $self->new_node($parent, @_);

    if ($self->[$#$self]->[0] eq 'tag') {
	push(@{$self->[$#$self]}, @{$node});
    } else {
	push(@{$parent}, @{$node});
    };

    return $node;
};

# Prepends a Comment to the XML node
sub comment {
    my $self = shift;
    my $comment = shift;

    if ($self->[0] eq 'root') {
	return;
    };

    my $offset = 4;
    my $parent = $self->[0]->[3];

    foreach my $e (@{$parent}[$offset .. $#{$parent}]) {
	$offset++;
	if ($e eq $self->[0]) {
	    last;
	};
    };

    my $pos_e = $parent->[$offset - 2];

    xml_escape($comment);

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

sub to_xml {
    my $self = shift;
    return _render(0, $self);
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

sub dom {
    my $self = shift;
    my $dom = Mojo::DOM->new(xml => 1);
    $dom->tree($self);
    return $dom;
};

1;
