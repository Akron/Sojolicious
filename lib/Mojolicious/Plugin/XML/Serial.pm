package Mojolicious::Plugin::XML::Serial;
use Mojo::Base 'Mojo::DOM';
use Mojo::ByteStream 'b';

use constant {
  I         => '  ',
  SERIAL_NS => 'http://sojolicio.us/ns/xml-serial',
  PI        => '<?xml version="1.0" encoding="UTF-8" '.
               'standalone="yes"?>'
};


# Construct new serial object
sub new {
  my $class = shift;

  # Create from parent class
  if ( ref($class)             ||
       !$_[0]                  ||
       (index($_[0],'<') >= 0) ||
       ( (@_ % 2) == 0 && ref( $_[1] ) ne 'HASH' ) ) {

    return $class->SUPER::new(@_);
  }

  # Create as node
  else {
    my $name = shift;
    my $att  = shift if (ref( $_[0] ) eq 'HASH');
    my $text = shift;

    # Node content
    my $element = qq(<$name xmlns:serial=").SERIAL_NS.'"';
    if ($text) {
      $element .= ">$text</$name>";
    } else {
      $element .= ' />';
    };

    # Create root element by parent class
    my $root = $class->SUPER::new( PI . $element, xml => 1 );

    # Transform special attributes
    foreach my $special ( grep( index($_, '-') == 0, keys %$att ) ) {
      $att->{'serial:' . substr($special,1) } =
	delete $att->{$special};
    };

    # Add attributes to node
    $root->at('*')->attrs($att);

    return $root;
  };
};


# Append a new child node to the XML Node
sub add {
  my $self = shift;

  # If root use first element
  if (!$self->parent && $self->tree->[1]->[0] eq 'pi') {
    $self = $self->at('*');
  };

  my ($node, $comment);

  # Node is a node object
  if (ref( $_[0] )) {
    $node    = $self->SUPER::new( shift->to_xml );
    $comment = shift;

    # Push namespaces to new root
    my $root_attr = $node->root->at('*')->attrs;
    foreach ( grep( index($_,'xmlns:') == 0, keys %{ $root_attr } ) ) {
      $_ = substr($_,6);
      $self->add_ns( $_ => delete $root_attr->{'xmlns:'.$_} );
    };

    # Push extensions to new root
    my $root = $self->at(':root');
    if (exists $root_attr->{'serial:ext'}) {
      my $ext = $root->attrs('serial:ext') || ();
      $root->attrs(
	'serial:ext' =>
	  join(';', $ext, split(';', $root_attr->{'serial:ext'}))
	);
    };

    # Delete pi from node
    if (ref($node->tree->[1]) eq 'ARRAY' &&
	  $node->tree->[1]->[0] eq 'pi') {
      splice( @{ $node->tree }, 1,1 );
    };

    # Append new node
    $self->append_content($node);
    $node = $self->children->[-1];
  }

  # Node is a string
  else {
    my $name = shift;
    my $att  = shift if (ref( $_[0] ) eq 'HASH');
    my $text = shift;
    $comment = shift;

    my $string = "<$name />";
    $string    = "<$name>$text</$name>" if defined $text;

    # Append new node
    $self->append_content($string);
    $node = $self->children->[-1];

    # Transform special attributes
    foreach my $special ( grep( index($_, '-') == 0, keys %$att ) ) {
      $att->{'serial:' . substr($special,1) } =
	delete $att->{$special};
    };

    # Add attributes to node
    $node->attrs($att);
  };

  # Add comment
  $node->comment($comment) if $comment;

  return $node;
};


# Add namespace to root
sub add_ns {
  my $self   = shift;
  my $prefix = $_[1] ? ':'.shift : '';
  $self->root->at('*')->attrs( 'xmlns'.$prefix => shift );
  return $prefix;
};


# Prepend a comment to the XML node
sub comment {
  my $self    = shift;
  $self->prepend('<!--' . b( shift )->xml_escape . '-->');
  return $self;
};


# Render as pretty xml
sub to_pretty_xml {
  my $self = shift;
  return _render_pretty(0, $self->tree);
};


# Render subtrees with pretty printing
sub _render_pretty {
  my $i    = shift; # Indentation
  my $tree = shift;

  my $e = $tree->[0];

  # No element
  warn 'No element' and return unless $e;

  # Element is tag
  if ($e eq 'tag') {
    my $subtree =
      [
	@{ $tree }[ 0 .. 2 ],
	[
	  @{ $tree }[ 4 .. $#$tree ]
	]
      ];

    return _element($i, $subtree);
  }

  # Element is text
  elsif ($e eq 'text') {

    my $escaped = $tree->[1];

    for ($escaped) {
      next unless $_;

      # Trim whitespace from both ends
      s/[\s\t\n]+$//;
      s/^[\s\t\n]+//;

      # Escape
      $_ = b($_)->xml_escape;
    };

    return $escaped;
  }

  # Element is comment
  elsif ($e eq 'comment') {
    my $comment = join("\n". I . I . ( I x $i ), # Todo: Why I.I ?
		       split('; ', $tree->[1]));
    return "\n".(I x $i).'<!-- '.$comment." -->\n";
  }

  # Element is processing instruction
  elsif ($e eq 'pi') {
    return (I x $i) . '<?' . $tree->[1] . "?>\n";

  }

  # Element is root
  elsif ($e eq 'root') {

    my $content;

    # Pretty print the content
    foreach my $child_e_i (1 .. $#$tree) {
      $content .=
	_render_pretty( $i, $tree->[$child_e_i] );
    };

    return $content;
  };
};


# Render element with pretty printing
sub _element ($$) {
  my $i = shift;

  my ($type,
      $qname,
      $attr,
      $child) = @{ $_[0] };

  # Is the qname valid?
  warn $qname.' is no valid QName'
    unless $qname =~ /^(?:[a-zA-Z_]+:)?[^\s]+$/;

  # Start start tag
  my $content = (I x $i) . '<' . $qname;

  # Add attributes
  $content .= _attr((I x $i).(' ' x ( length($qname) + 2)), $attr);

  # Has the element a child?
  if ($child->[0]) {

    # Close start tag
    $content .= '>';

    # There is only a textual child - no indentation
    if (!$child->[1] &&
	  ($child->[0] && $child->[0]->[0] eq 'text')
	) {

      # Special content treatment
      if (exists $attr->{'serial:type'}) {

	# With base64 indentation
	if ($attr->{'serial:type'} eq 'base64') {
	  my $b64_string = $child->[0]->[1];
	  $b64_string =~ s/\s//g;

	  $content .= "\n";

	  $content .= I x ($i + 1);
	  $content .= join( "\n" . ( I x ($i + 1) ),
			    ( unpack '(A60)*', $b64_string ) );
	  $content .= "\n" . (I x $i);
	}

	# Escape
	elsif ($attr->{'serial:type'} eq 'escape') {
	  $content .= b($child->[0]->[1])->xml_escape;
	}

		# No special content treatment indentation
		else {
		    $content .= $child->[0]->[1];
		};
	    }

	    # No special content treatment indentation
	    else {
		$content .= $child->[0]->[1];
	    };
	}

	# Treat children special
	elsif (exists $attr->{'serial:type'} &&
	       $attr->{'serial:type'} eq 'raw') {
	    foreach my $e_child (@$child) {
		$content .= __PACKAGE__->SUPER::new(tree => $e_child)->to_xml;
	    };
	}

	# There are some childs
	else {
	    $content .= "\n";

	    # Loop through all child elements
	    foreach my $child_e (@$child) {

		# Render next element
		$content .= _render_pretty($i+1, $child_e);
	    };

	    # Correct Indent
	    $content .= (I x $i);

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

    delete $attr{$_} foreach grep(/^(?:xmlns:)?serial:?/, keys %attr);

    # prepare attribute values
    foreach (values %attr) {
	$_ = b($_)->xml_escape->quote;
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

sub AUTOLOAD {
    my $self = shift;
    my @param = @_;

    my ($package, $method) = our $AUTOLOAD =~ /^([\w\:]+)\:\:(\w+)$/;

    {
	no strict 'refs';

	my $root = $self->at(':root');

	if (my $ext_string = $root->attrs('serial:ext')) {
	    foreach my $ext ( split(';', $ext_string ) ) {
		if (defined *{ $ext.'::'.$method }) {
		    return *{ $ext.'::'.$method }->($self, @param);
		};
	    };
	};
    };

    Carp::croak(qq/Can't locate object method "$method" via package "$package"/);
    return;

};

1;

__END__

=pod

=head1 NAME

Mojolicious::Plugin::XML::Serial - Simple XML constructor

=head1 SYNOPSIS

  use Mojolicious::Plugin::XML::Serial;

  my $xml = Mojolicious::Plugin::XML::Serial->new;
  $xml->add('link' => { rel => 'foo'}, 'bar');

  # Mojolicious
  $self->plugin('XML::Serial');

  # Mojolicious::Lite
  plugin 'XML::Serial';

=head1 METHODS

L<Mojolicious::Plugin::XML::Serial> inherits all methods from
L<Mojo::DOM> and implements the following new ones.

=head2 C<new>

  my $serial = Mojolicious::Plugin::XML::Serial->new(<<'EOF');

  my $serial = $serial->new('Document', {id => 'new'}, 'My Doc');

=head2 C<add>

  my $serial = $serial->add('Data', { -type => 'base64' }, 'PdGzjvj..');

  my $serial = $serial->add('a', { href => 'http://...' });
  my $node = $serial->new('strong', 'My Doc');
  $serial->add($node);

Appends a new Element to the document root and returns a
C<Mojolicious::Plugin::XML::Serial> object.

Allows for special content types with C<-type> attributes:

=hover2

=item C<base64> Indents the content and automatically linebreaks after
                60 characters.

=item C<escape> XML escapes the content of the node.

=back

=head2 C<add_ns>

  $serial->add_ns('fun' => 'http://sojolicio.us/fun');
  $serial->add_ns('http://sojolicio.us/fun');

Add namespace to the node's root.
The first parameter gives the prefix, the second one
the namespace. The prefix parameter is optional.


=head2 C<comment>

  $node = $node->comment('Resource Descriptor');

Prepends a comment to the XRD node.

=head2 C<to_pretty_xml>

  print $xml->to_pretty_xml;

Returns a stringified, pretty printed XML document.

=head1 DEPENDENCIES

L<Mojolicious>.

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2011, Nils Diewald.

This program is free software, you can redistribute it
and/or modify it under the same terms as Perl.

=cut
