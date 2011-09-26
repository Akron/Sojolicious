package Mojolicious::Plugin::XML::Serial;
use Mojo::Base 'Mojo::DOM';
use Mojo::ByteStream 'b';
use Mojo::Loader;

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
    my $root = $class->SUPER::new( PI . $element, xml => 1 );

    # Transform special attributes
    foreach my $special ( grep( index($_, '-') == 0, keys %$att ) ) {
      $att->{'serial:' . substr($special,1) } =
	delete $att->{$special};
    };

    # Add attributes to node
    $element = $root->at('*');
    $element->attrs($att);

    # The class is derived
    if ($class ne __PACKAGE__) {
      # Set namespace if given
      no strict 'refs';
      if (defined ${ $class.'::NS' }) {
	$element->attrs(xmlns => ${ $class.'::NS' });
      };
    };

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


# Append a new child node to the XML Node
# Prepend prefix if necessary.
sub add_pref {
  my $self   = shift;
  my $element = $self->add(@_);
  return $element if $element->tree->[0] ne 'tag';

  my $caller = caller;
  my $class  = ref($self);

  my $name = $element->tree->[1];

  if ($name &&
	($caller && $class) &&
	  ($caller ne $class)) {
    {
      no strict 'refs';
      if ((my $prefix = ${ $caller.'::PREFIX' }) &&
	  ${ $caller.'::NS' }) {
	$element->tree->[1] = $prefix.':'.$name if $prefix;
      };
    };
  };

  return $element;

};

# Add extension to document
sub add_extension {
  my $self      = shift;

  # New Loader
  my $loader = Mojo::Loader->new;

  # Use root element
  $self = $self->root->at('*');

  # Get ext string
  my @ext = split( /\s*;\s*/, $self->attrs('serial:ext') || '');

  # Try all given extension names
  foreach my $ext (@_) {

    # Unable to load extension
    if (my $e = $loader->load($ext)) {
      Carp::croak( "Exception: $e" ) if ref $e;
      Carp::croak(qq{Unable to load extension "$ext"});
      next;
    };

    # Add extension to extensions list
    push(@ext, $ext);

    # Add namespace for extension
    {
      no strict 'refs';
      if (defined ${ $ext . '::NS' } &&
	  defined ${ $ext . '::PREFIX' }) {
	$self->add_ns(${ $ext . '::PREFIX' } =>
			${ $ext . '::NS' });
      };
    };
  };

  # Save extension list as attribute
  $self->attrs('serial:ext' => join(';', @ext));

  return;
};


# Add namespace to root
sub add_ns {
  my $self   = shift;

  # prefix namespace if existent
  my $prefix = $_[1] ? ':' . shift : '';

  # Save namespace as attribute
  $self->root->at('*')->attrs( 'xmlns' . $prefix => shift );
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
	     map($_ . '=' . $attr{$_}, keys %attr ) );
    };

    # Return nothing
    return '';
};


# Autoload for extensions
sub AUTOLOAD {
  my $self = shift;
  my @param = @_;

  # Split parameter
  my ($package, $method) = our $AUTOLOAD =~ /^([\w\:]+)\:\:(\w+)$/;

  # Choose root element
  my $root = $self->root->at('*');

  # Get ext string
  my $ext_string;
  if ($ext_string = $root->attrs('serial:ext')) {
    no strict 'refs';

    foreach my $ext ( split(';', $ext_string ) ) {
      # Method does not exist in extension
      next unless  defined *{ $ext.'::'.$method };

      # Release method
      return *{ $ext.'::'.$method }->($self, @param);
    };
  };

  my $errstr = qq{Can't locate object method "$method" via package "$package"};
  $errstr .= qq{ with extensions "$ext_string"} if $ext_string;

  Carp::croak($errstr);
  return;
};


1;


__END__

=pod

=head1 NAME

Mojolicious::Plugin::XML::Serial - Simple XML constructor

=head1 SYNOPSIS

  use Mojolicious::Plugin::XML::Serial;

  my $xml = Mojolicious::Plugin::XML::Serial->new('entry');

  my $env = $xml->add('fun:env' => { foo => 'bar' });

  $xml->add_ns('fun' => 'http://sojolicio.us/ns/fun');

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

=item C<armour(:n)?> Indent the content and automatically
                     introduce linebreaks after every
                     C<n> characters.
                     Intended for base64 encoded data.
                     Defaults to 60 characters

=item C<escape> XML escape the content of the node.

=item C<raw> Treat children as raw data (no pretty printing.

=back

=head2 C<add_pref>

C<add_pref> is similar to C<add> and needs the same parameters.
However, if used in an extension context, it will prefix the element
name for the namespace. In base context, no prefix is introduced.

=head2 C<comment>

  $node = $node->comment('Resource Descriptor');

Prepends a comment to the XRD node.

=head2 C<add_ns>

  $serial->add_ns('fun' => 'http://sojolicio.us/fun');
  $serial->add_ns('http://sojolicio.us/fun');
  $serial->add('fun:test' => { foo => 'bar' }, 'Works!');

Add namespace to the node's root.
The first parameter gives the prefix, the second one
the namespace. The prefix parameter is optional.

=head2 C<add_extension>

  $serial->add_extension('Fun','Atom');

Add an array of packages as extensions to the root
of the document.

=head2 C<to_pretty_xml>

  print $xml->to_pretty_xml;

Returns a stringified, pretty printed XML document.

=head1 EXTENSIONS

L<Mojolicious::Plugin::XML::Serial> allows for inheritance
and thus provides two ways of extending the functionality:
By using a derived class as a base class or by extending a
base class with the C<add_extension> method.

  package Fun;
  use Mojo::Base 'Mojolicious::Plugin::XML::Serial';

  our $NS     = 'http://sojolicio.us/ns/fun';
  our $PREFIX = 'fun';

  sub add_happy {
    my $self = shift;
    my $word = shift;

    my $cool = $self->add('Cool');

    my $cry = uc($word) . '!!! \o/ ';

    $cool->add_pref('Happy', {foo => 'bar'}, $cry);
  };

Then use this object in your app:

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

The defined namespace C<$NS> is introduced as the documents
namespaces. The prefix C<$PREFIX> is not used.
The behaviour of the C<add_pref> method in this example is exactly
the same as the C<add> method.

This package can be used as an extension as well:

  package main;
  use Mojo::Base 'Mojolicious::Plugin::XML::Serial';
  my $obj = Mojolicious::Plugin::XML::Serial->new('object');
  $obj->add_extension('Fun');
  $obj->add_happy('Yeah!');
  print $obj->to_pretty_xml;

  # <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
  # <object xmlns:fun="http://sojolicio.us/ns/fun">
  #   <Cool>
  #     <fun:Happy foo="bar">YEAH!!!! \o/ </fun:Happy>
  #   </Cool>
  # </object>

The defined namespace C<$NS> is introduced with the prefix C<$PREFIX>.
The prefix is prepend to all elements added by C<add_pref>.
All elements added by C<add> have no prefixes prepended.

New extensions can always be introduced to a base class,
whether derived or not.

  package Atom;
  use Mojo::Base 'Mojolicious::Plugin::XML::Serial';

  our $PREFIX = 'atom';
  our $NS = 'http://www.w3.org/2005/Atom';

  # Add id
  sub add_id {
    my $self = shift;
    my $id   = shift;
    return unless $id;
    $self->at('*')->attrs('xml:id' => $id);
    $self->add_pref('id', $id);
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


=head1 DEPENDENCIES

L<Mojolicious>.

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2011, Nils Diewald.

This program is free software, you can redistribute it
and/or modify it under the same terms as Perl.

=cut
