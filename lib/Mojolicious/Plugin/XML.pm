package Mojolicious::Plugin::XML;
use Mojo::Base 'Mojolicious::Plugin';
use Mojolicious::Plugin::XML::Base;
use Mojo::Loader;

# Namespace for xml classes and extensions
has namespace => 'Mojolicious::Plugin::XML';

my %base_classes;

# Register Plugin
sub register {
  my ($plugin, $mojo, $param) = @_;

  # Load parameter from Config file
  if (my $config_param = $mojo->config('XML')) {
    $param = { %$config_param, %$param };
  };

  # Set Namespace
  if (exists $param->{namespace}) {
    $plugin->namespace(delete $param->{namespace});
  };

  # Start Mojo::Loader instance
  my $loader = Mojo::Loader->new;

  # Create new XML helpers
  foreach my $helper (keys %$param) {
    my @helper = @{ $param->{ $helper } };
    my $base = shift(@helper);

    my $module = $plugin->namespace . '::' . $base;

    # Load module if not loaded
    if (!exists $base_classes{$module}) {

      # Todo: Respect delegate

      # Load base class
      if (my $e = $loader->load($module)) {
	my $log = $mojo->log;
	$log->error("Exception: $e")  if ref $e;
	$log->error(qq{Unable to load base class "$base"});
	next;
      };

      # Establish mime types
      {
	no strict 'refs';

	if ((my $mime   = ${$module . '::MIME'}) &&
	      (my $prefix = ${$module . '::PREFIX'})) {

	  # Apply mime type
	  $mojo->types->type($prefix => $mime);
	};
      };

      # module loaded
      $base_classes{$module} = 1;
    };

    # Code generation for ad-hoc helper
    my $code = '
sub {
  shift; # Controller or app
  my $doc = ' . $plugin->namespace . '::' . $base . '->new( @_ );';

    if (@helper) {
      $code .= '
  $doc->add_extension(' .
    join(',', map( '"' . $plugin->namespace . '::' . $_ . '"', @helper)) .
      ");\n";
    };
    $code .= '  return $doc;'."\n};";

    my $code_ref = eval $code;
    if ($@) {
      die $@ . ':' . $!;
    };

    # Create helper
    $mojo->helper($helper, $code_ref );

  };

  # Plugin wasn't registered before
  unless (exists $mojo->renderer->helpers->{'new_xml'}) {

    # Default 'new_xml' helper
    $mojo->helper(
      'new_xml' => sub {
	return Mojolicious::Plugin::XML::Base->new( @_ );
      });


    # Add 'render_xml' helper
    $mojo->helper(
      'render_xml' => sub {
	my $c      = shift;
	my $xml    = shift;
	my $format = 'xml';

	if (my $class = ref $xml) {
	  no strict 'refs';
	  if (defined ${ $class . '::MIME' } &&
		defined ${ $class . '::PREFIX' }) {
	    $format = ${ $class . '::PREFIX' };
	  };
	};

	# render XML with correct mime type
	return $c->render_data($xml->to_pretty_xml,
			       'format' => $format,
			       @_);
      });
  };
};

1;

__END__

=pod

=head1 NAME

Mojolicious::Plugin::XML - XML generation with Mojolicious

=head1 SYNOPSIS

  # Mojolicious
  $mojo->plugin(XML => {
    namespace    => 'Mojolicious::Plugin::XML',
    new_activity => ['Atom', 'ActivityStreams'],
    new_hostmeta => ['XRD',  'HostMeta'],
    new_myXML    => ['Base', 'Atom', 'Atom-Threading']
  });

  my $xml = $self->new_xml('entry');
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

  $c->render_xml($xml);

  # Content-Type: application/xml
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

  my $xrd = $self->new_hostmeta;
  $xrd->add_host('sojolicio.us');
  $c->render_xml($xrd);

  # Content-Type: application/xrd+xml
  # <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
  # <XRD xmlns="http://docs.oasis-open.org/ns/xri/xrd-1.0"
  #      xmlns:hm="http://host-meta.net/xrd/1.0"
  #      xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
  #   <hm:Host>sojolicio.us</hm:Host>
  # </XRD>

=head1 DESCRIPTION

L<Mojolicious::Plugin::XML> is a plugin to support
XML documents based on L<Mojolicious::Plugin::XML::Base>.


=head1 ATTRIBUTES

=head2 C<namespace>

  $xml->namespace('MyXMLFiles::XML');
  print $xml->namespace;

The namespace of all XML plugins.
Defaults to C<Mojolicious::Plugin::XML>

=head1 METHODS

=head2 C<register>

  # Mojolicious
  $mojo->plugin(XML => {
    namespace    => 'Mojolicious::Plugin::XML',
    new_activity => ['Atom', 'ActivityStreams']
  });

  # Mojolicious::Lite
  plugin 'XML' => {
    namespace    => 'Mojolicious::Plugin::XML',
    new_activity => ['Atom', 'ActivityStreams']
  };

Called when registering the plugin.
Accepts the attributes mentioned as parameters as
well as new xml profiles.
All parameters can be set either on registration or
as part of the configuration file with the key C<XML>.


=head1 HELPERS

=head2 C<new_xml>

To create a helper extending the base class,
use 'Base' as the base class:

  $mojo->plugin(XML => {
    new_myXML => ['Base', 'Atom']
  });

=head2 C<render_xml>

  $c->render_xml($xml)
  $c->render_xml($xml, code => 404)

Render documents based on L<Mojolicious::Plugin::XML::Base>.
You can associate a mime type to be used with the document by
providing a class variable in your base class:

=over 2

=item C<$MIME> Mime Type of the XML document

=back

So a new base class can be written as:

  package Fun;
  use Mojo::Base 'Mojolicious::Plugin::XML::Base';

  our $NAMESPACE = 'http://sojolicio.us/ns/fun';
  our $PREFIX    = 'fun';
  our $MIME      = 'application/fun+xml';

  sub add_happy {
    my $self = shift;
    my $word = shift;
    $self->add('Happy', '\o/' . $word . '\o/');
  };

=head1 DEPENDENCIES

L<Mojolicious>,
L<Mojolicious::Plugin::XML::Base>.

=head1 AVAILABILITY

  https://github.com/Akron/Sojolicious

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2011-2012, Nils Diewald.

This program is free software, you can redistribute it
and/or modify it under the same terms as Perl.

=cut


