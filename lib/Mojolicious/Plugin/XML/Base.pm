package Mojolicious::Plugin::XML::Base;
use Mojo::Base 'Mojo::DOM';
use Mojo::ByteStream 'b';
use Mojo::Loader;

# Todo: use attributes for get and add
#       sub title : add {};
#       sub title : get {};

use constant {
  I         => '  ',
  SERIAL_NS => 'http://sojolicio.us/ns/xml-serial',
  PI        => '<?xml version="1.0" encoding="UTF-8" '.
               'standalone="yes"?>'
};

# Construct new serial object
sub new {
  my $class = shift;

# Todo: Is often called with class = '<...>' - this seems to be totally wrong!!!


  # Todo: Change order for speed (often 'charset' is $_[0])
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
    my $element = qq(<$name xmlns:serial=") . SERIAL_NS . '"';

    # Text is given
    if ($text) {
      $element .= ">$text</$name>";
    }

    # Empty element
    else {
      $element .= ' />';
    };

    # Create root element by parent class
    my $root = $class->SUPER::new( PI . $element );
    $root->xml(1);

    # Transform special attributes
    foreach my $special ( grep( index($_, '-') == 0, keys %$att ) ) {
      $att->{'serial:' . substr($special,1) } =
	lc(delete $att->{$special});
    };

    # Add attributes to node
#     my $root_e = $root->_root_element;
#     $root_e->[2] = $att;
    my $root_e = $root->at(':root');
    $root_e->attrs($att);

    # The class is derived
    if ($class ne __PACKAGE__) {
      # Set namespace if given
      no strict 'refs';
      if (defined ${ $class.'::NAMESPACE' }) {
	$root_e->attrs(xmlns => ${ $class.'::NAMESPACE' });
#	$root_e->[2]->{xmlns} = ${ $class.'::NAMESPACE' };
      };
    };

    return $root;
  };
};


# Append a new child node to the XML Node
sub add {
  my $self    = shift;
  my $element = $self->_add_clean(@_);

  # Prepend no prefix
  if (index($element->tree->[1],'-') == 0) {
    $element->tree->[1] = substr($element->tree->[1], 1);
    return $element;
  };

  return $element if $element->tree->[0] ne 'tag';

  # Prepend prefix if necessary.
  my $caller = caller;
  my $class  = ref($self);

  my $name = $element->tree->[1];

  if ($name &&
	($caller && $class) &&
	  ($caller ne $class)) {
    no strict 'refs';
    if ((my $prefix = ${ $caller.'::PREFIX' }) &&
	  ${ $caller.'::NAMESPACE' }) {
      $element->tree->[1] = $prefix.':'.$name if $prefix;
    };
  };

  return $element;
};


# todo:
# sub try_further {
# };
#
# usage:
# sub get_author {
#   return $autor or $self->try_further;
# };

# Append a new child node to the XML Node
sub _add_clean {
  my $self = shift;

  # If root use first element
  if (!$self->parent &&
#	$self->tree->[1]->[0] &&
	  ($self->tree->[1]->[0] eq 'pi')) {
    $self = $self->at('*');
  };

  my ($node, $comment);

  # Node is a node object
  if (ref( $_[0] )) {
    $node    = $self->SUPER::new( shift->to_xml );
    $comment = shift;

    # Push namespaces to new root
    my $root_attr =      $node->_root_element->[2];
    foreach ( grep( index($_,'xmlns:') == 0, keys %{ $root_attr } ) ) {
      $_ = substr($_,6);
      $self->add_namespace( $_ => delete $root_attr->{'xmlns:'.$_} );
    };

    # Delete namespace information, if already set
    if (exists $root_attr->{xmlns}) {
      my $ns = $self->namespace;
      if ($ns && $root_attr->{xmlns} eq $ns) {
	delete $root_attr->{xmlns};
      };
    };

    # Push extensions to new root
    my $root = $self->_root_element;
    if (exists $root_attr->{'serial:ext'}) {
      my $ext = $root->[2]->{'serial:ext'} || '';
      $root->[2]->{'serial:ext'} =
	join("; ", $ext, split(/;\s/, $root_attr->{'serial:ext'}))
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


# Add extension to document
sub add_extension {
  my $self = shift;

  # Get root element
  my $root = $self->_root_element or return;

  # New Loader
  my $loader = Mojo::Loader->new;

  # Get ext string
  my @ext = split(/;\s/, $root->[2]->{'serial:ext'} || '');

  my $loaded = 0;

  # Try all given extension names
  while (my $ext = shift( @_ )) {

    # Unable to load extension
    if (my $e = $loader->load($ext)) {
      warn "Exception: $e"  if ref $e;
      warn qq{Unable to load extension "$ext"};
      next;
    };

    {
      no strict 'refs';

      # Check for extension delegation
      if (defined ${ $ext . '::DELEGATE' }) {
	$ext = ${ $ext . '::DELEGATE' };

	# No recursion for security
	if (my $e = $loader->load($ext)) {
	  warn "Exception: $e" if ref $e;
	  warn qq{Unable to load delegated extension "$ext"};
	  next;
	};
      };

      # Add extension to extensions list
      push(@ext, $ext);
      $loaded++;

      # Add namespace for extension
      if (defined ${ $ext . '::NAMESPACE' } &&
	    defined ${ $ext . '::PREFIX' }) {

	$root->[2]->{ 'xmlns:' . ${ $ext . '::PREFIX' } } =
	  ${ $ext . '::NAMESPACE' };
      };
    };
  };

  # Save extension list as attribute
  $root->[2]->{'serial:ext'} = join("; ", @ext);

  return $loaded;
};


# Add namespace to root
sub add_namespace {
  my $self   = shift;

  # prefix namespace if existent
  my $prefix = $_[1] ? ':' . shift : '';

  # Get root element
  my $root = $self->_root_element or return;

  # Save namespace as attribute
  $root->[2]->{ 'xmlns' . $prefix } = shift;
  return $prefix;
};


# Prepend a comment to the XML node
sub comment {
  my $self = shift;
  $self->prepend('<!--' . b( shift )->xml_escape . '-->');
  return $self;
};


# Render as pretty xml
sub to_pretty_xml {
  return _render_pretty(0, shift->tree);
};


# Render subtrees with pretty printing
sub _render_pretty {
  my $i    = shift; # Indentation
  my $tree = shift;

  my $e = $tree->[0];

  # No element
  Carp::croak('No element') and return unless $e;

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
		       split(/;\s/, $tree->[1]));
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
  Carp::croak($qname.' is no valid QName')
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
	if ($attr->{'serial:type'} =~ /^armour(?::(\d+))?$/) {
	  my $n = $1 || 60;

	  my $string = $child->[0]->[1];

	  # Delete whitespace
	  $string =~ tr{\t-\x0d }{}d;

	  $content .= "\n";

	  # Introduce newlines after n characters
	  $content .= I x ($i + 1);
	  $content .= join( "\n" . ( I x ($i + 1) ),
			    ( unpack '(A'.$n.')*', $string ) );
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
	$content .= __PACKAGE__->SUPER::new( tree => $e_child )->to_xml;
      };
    }

    # There are some childs
    else {
      $content .= "\n";

      # Loop through all child elements
      foreach my $child_e (@$child) {

	# Render next element
	$content .= _render_pretty( $i + 1, $child_e );
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

  # Return content
  return $content;
};


# Render attributes with pretty printing
sub _attr ($$) {
    my $indent_space = shift;
    my %attr         = %{$_[0]};

    # Delete special attributes
    delete $attr{$_} foreach grep($_ eq 'xmlns:serial' ||
				    index($_,'serial:') == 0, keys %attr);

    # Prepare attribute values
    foreach (values %attr) {
	$_ = b($_)->xml_escape->quote;
    };

    # Return indented attribute string
    if (keys %attr) {
      return ' ' .
	join("\n".$indent_space,
	     map($_ . '=' . $attr{$_}, sort keys %attr ) );
    };

    # Return nothing
    return '';
};


# Get root element (not as an object)
sub _root_element {
  my $self = shift;

  # Todo: Optimize! Often called!

  # Find root (Based on Mojo::DOM::root)
  my $root = $self->tree;
  my $tag;

  # Root is root node
  if ($root->[0] eq 'root') {
    my $i = 1;
    while ($root->[$i] &&
	     $root->[$i]->[0] &&
	       $root->[$i]->[0] ne 'tag') {
      $i++;
    };
    $tag = $root->[$i];
  }

  # Root is a tag
  else {
    while ($root->[0] eq 'tag') {
      $tag = $root;
      last unless my $parent = $root->[3];
      $root = $parent;
    };
  };

  return $tag;
};


# Autoload for extensions
sub AUTOLOAD {
  my $self = shift;
  my @param = @_;

  # Split parameter
  my ($package, $method) = our $AUTOLOAD =~ /^([\w\:]+)\:\:(\w+)$/;

  # Choose root element
  my $root = $self->_root_element;

  # Get ext string
  my $ext_string;
  if ($ext_string = $root->[2]->{'serial:ext'}) {
    no strict 'refs';

    foreach my $ext ( split(/;\s/, $ext_string ) ) {
      # Method does not exist in extension
      next unless  defined *{ $ext.'::'.$method };

      # Release method
      return *{ $ext.'::'.$method }->($self, @param);
    };
  };

  my $errstr = qq{Can't locate object method "$method" via package "$package"};
  $errstr .= qq{ with extensions "$ext_string"} if $ext_string;

  warn $errstr;
  return;
};

1;

__END__

=pod

=head1 NAME

Mojolicious::Plugin::XML::Base - XML generator base class

=head1 SYNOPSIS

  my $xml = Mojolicious::Plugin::XML::Base->new('entry');
  my $env = $xml->add('fun:env' => { foo => 'bar' });
  $xml->add_namespace('fun' => 'http://sojolicio.us/ns/fun');
  my $data = $env->add('data' => { type  => 'text/plain',
                                   -type => 'armour:30'
			         } => <<'B64');
    VGhpcyBpcyBqdXN0IGEgdGVzdCBzdHJpbmcgZm
    9yIHRoZSBhcm1vdXIgdHlwZS4gSXQncyBwcmV0
    dHkgbG9uZyBmb3IgZXhhbXBsZSBpc3N1ZXMu
  B64

  $data->comment('This is base64 data!');

  print $xml->to_pretty_xml;

  # <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
  # <entry xmlns:fun="http://sojolicio.us/ns/fun">
  #   <fun:env foo="bar">
  #
  #     <!-- This is base64 data! -->
  #     <data type="text/plain">
  #       VGhpcyBpcyBqdXN0IGEgdGVzdCBzdH
  #       JpbmcgZm9yIHRoZSBhcm1vdXIgdHlw
  #       ZS4gSXQncyBwcmV0dHkgbG9uZyBmb3
  #       IgZXhhbXBsZSBpc3N1ZXMu
  #     </data>
  #   </fun:env>
  # </entry>

=head1 DESCRIPTION

L<Mojolicious::Plugin::XML::Base> allows for the simple creation
of serialized XML documents with multiple namespaces and
pretty printing.

=head1 METHODS

L<Mojolicious::Plugin::XML::Base> inherits all methods from
L<Mojo::DOM> and implements the following new ones.

=head2 C<new>

  my $xml = Mojolicious::Plugin::XML::Base->new(<<'EOF');
  <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
  <entry>
    <fun>Yeah!</fun>
  <entry>
  EOF

  my $xml = Mojolicious::Plugin::XML::Base->new('Document');
  my $xml = Mojolicious::Plugin::XML::Base->new('Document',
                                                { foo => bar });
  my $xml = $xml->new('Document', {id => 'new'}, 'My Doc');

Construct a new L<Mojolicious::Plugin::XML::Base> object.
Accepts either all parameters supported by L<Mojo::DOM> or
all parameters supported by C<add>.

=head2 C<add>

  my $xml = Mojolicious::Plugin::XML::Base->new('Document');
  $xml = $xml->add('Element');
  $xml = $xml->add('Element', { type => 'text/plain' });
  $xml = $xml->add('Element', { type => 'text/plain' }, 'Hello World!');
  $xml = $xml->add('Element', 'Hello World!');
  $xml = $xml->add('Element', 'Hello World!', 'This is a comment!');
  $xml = $xml->add('Data', { -type => 'base64' }, 'PdGzjvj..');

  my $element = $xml->new('Element', 'Hello World!');
  $xml->add($element);

Append a new Element to a C<Mojolicious::Plugin::XML::Base> object.
Returns the root node of the added C<Mojolicious::Plugin::XML::Base>
object.

It accepts either C<Mojolicious::Plugin::XML::Base> objects to
be added, or newly defined elements.
Parameters to define elements are a tag name, an optional Hash reference
including all attributes of the XML element, an optional text content,
and an optional comment on the element.
If the comment should be introduced without text content, text content
has to be undef.

For rendering element content, a special C<-type> attribute can be used:

=over 2

=item C<escape>      XML escape the content of the node.

=item C<raw>         Treat children as raw data (no pretty printing).

=item C<armour(:n)?> Indent the content and automatically
                     introduce linebreaks after every
                     C<n> characters.
                     Intended for base64 encoded data.
                     Defaults to 60 characters

=back

In extension context (see L<Extensions>), a potential prefix is automatically
prepended. To prevent prefixing in extension context, prepend a C<-> to
the element name. See L<Extensions> for further information.

  $self->add('Link', { foo => 'bar' });
  $self->add('-Link', { foo => 'bar' });
  # Both <Link foo="bar" /> in normal context

=head2 C<comment>

  $node = $node->comment('Resource Descriptor');

Prepend a comment to the current node.

=head2 C<add_namespace>

  $xml->add_namespace('fun' => 'http://sojolicio.us/fun');
  $xml->add_namespace('http://sojolicio.us/fun');
  $xml->add('fun:test' => { foo => 'bar' }, 'Works!');

Add namespace to the node's root.
The first parameter gives the prefix, the second one
the namespace. The prefix parameter is optional.
Namespaces are always added to the document's root, that
means, they have to be unique in the scope of the whole
document.

=head2 C<add_extension>

  $xml->add_extension('Fun','Mojolicious::Plugin::XML::Atom');

Add an array of packages as extensions to the root
of the document. See L<Extensions> for further information.

=head2 C<to_pretty_xml>

  print $xml->to_pretty_xml;

Returns a stringified, pretty printed XML document.

=head1 EXTENSIONS

L<Mojolicious::Plugin::XML::Base> allows for inheritance
and thus provides two ways of extending the functionality:
By using a derived class as a base class or by extending a
base class with the C<add_extension> method.

For this purpose three class variables can be set:

=over 2

=item C<$NAMESPACE> Namespace of the extension.

=item C<$PREFIX> Preferred prefix to associate with the namespace.

=item C<$DELEGATE> Delegate extension request to a different module.

=back

These class variables can be defined in a derived XML::Base class.

  package Fun;
  use Mojo::Base 'Mojolicious::Plugin::XML::Base';

  our $NAMESPACE = 'http://sojolicio.us/ns/fun';
  our $PREFIX = 'fun';

  sub add_happy {
    my $self = shift;
    my $word = shift;

    my $cool = $self->add('-Cool');
    my $cry  = uc($word) . '!!! \o/ ';
    $cool->add('Happy', {foo => 'bar'}, $cry);
  };

You can use this derived object in your application as you
would do with any other object class.

  package main;
  use Fun;
  my $obj = Fun->new('Fun');
  $obj->add_happy('Yeah!');
  print $obj->to_pretty_xml;

  # <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
  # <Fun xmlns="http://sojolicio.us/ns/fun">
  #   <Cool>
  #     <Happy foo="bar">YEAH!!!! \o/ </Happy>
  #   </Cool>
  # </Fun>

The defined namespace C<$NAMESPACE> is introduced as the documents
namespaces. The prefix C<$PREFIX> is not used for any C<add>
method.

Without any changes to the class, you can use this module as an
extension as well.

  my $obj = Mojolicious::Plugin::XML::Base->new('object');
  $obj->add_extension('Fun');
  $obj->add_happy('Yeah!');
  print $obj->to_pretty_xml;

  # <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
  # <object xmlns:fun="http://sojolicio.us/ns/fun">
  #   <Cool>
  #     <fun:Happy foo="bar">YEAH!!!! \o/ </fun:Happy>
  #   </Cool>
  # </object>

The defined namespace C<$NAMESPACE> is introduced with the
prefix C<$PREFIX>. The prefix is prepended to all elements
added by C<add>, except for element names beginning with a C<->.

New extensions can always be introduced to a base class,
whether it is derived or not.

  package Atom;
  use Mojo::Base 'Mojolicious::Plugin::XML::Base';

  our $PREFIX = 'atom';
  our $NAMESPACE = 'http://www.w3.org/2005/Atom';

  # Add id
  sub add_id {
    my $self = shift;
    my $id   = shift;
    return unless $id;
    my $element = $self->add('id', $id);
    $element->parent->attrs('xml:id' => $id);
    return $self;
  };

  package main;
  use Fun;
  my $obj = Fun->new('Fun');
  $obj->add_extension('Atom');
  $obj->add_happy('Yeah!');
  $obj->add_id('1138');
  print $obj->to_pretty_xml;

  # <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
  # <Fun xmlns="http://sojolicio.us/ns/fun"
  #      xmlns:atom="http://www.w3.org/2005/Atom"
  #      xml:id="1138">
  #   <Cool>
  #     <Happy foo="bar">YEAH!!!! \o/ </Happy>
  #   </Cool>
  #   <atom:id>1138</atom:id>
  # </Fun>

With the C<add_extension> method, you define module names as extensions.
If the extension is part of the module but in a package with a different
name, you can define the C<$DELEGATE> variable in the module namespace
to link to the intended package.

  package Atom;
  use Mojo::Base 'Mojolicious::Controller';

  our $DELEGATE = 'Atom::Document';

  # ... (Controller methods)

  package Atom::Document;
  use Mojo::Base 'Mojolicious::Plugin::XML::Base';

  our $PREFIX = 'atom';
  our $NAMESPACE = 'http://www.w3.org/2005/Atom';

  # ... (Document methods)

Having, for example, a controller class 'Atom' with an appended document
package, you can load the controller class and use the document
class as the extension in your application.

  package main;
  use Mojolicious::Plugin::XML::Base;
  my $xml = Mojolicious::Plugin::XML::Base->new('feed');
  $xml->add_extension('Atom');

=head1 DEPENDENCIES

L<Mojolicious>.

=head1 AVAILABILITY

  https://github.com/Akron/Sojolicious

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2011, Nils Diewald.

This program is free software, you can redistribute it
and/or modify it under the same terms as Perl.

=cut
