package Mojolicious::Plugin::PortableContacts::Entry;
use Mojo::Base -base;
use Mojolicious::Plugin::XML::Base;

# todo - allow further valid labels

my $SINGULAR_RE = qr/^(?:id|
                        (?:preferred_user|nick|display_)?name|
                        published|
                        updated|
                        birthday|
                        anniversary|
                        gender|
                        note|
                        utc_offset|
                        connected)$/x;
my $PLURAL_RE = qr/^(?:email|
                       url|
                       phone_number|
                       im|
                       photo|
                       tag|
                       relationship|
                       organization|
                       addresse|
                       account)s$/x;
my $VALID_RE = qr(^$SINGULAR_RE|$PLURAL_RE$);
my $FORMATTED_RE = qr/^(?:formatted|streetAddress|description)$/;

# Return XML document
sub to_xml {
  return shift->_xml->to_pretty_xml;
};

# Return cleaned xml serialized object
sub _xml {
  my $self = shift;

  my $entry = Mojolicious::Plugin::XML::Base->new('entry');

  foreach my $key (keys %$self) {

    # Normal vattributes
    if (!ref $self->{$key} && $key =~ $SINGULAR_RE) {

      unless ($key eq 'note') {
	$entry->add($key, $self->{$key});
      } else {
	$entry->add($key => {-type => 'raw'} =>
		      '<![CDATA['.$self->{$key}.']]>');
      };
    }

    # Complex attributes
    else {
      if (ref($self->{$key}) eq 'HASH'  && $key =~ $SINGULAR_RE) {
	my $node = $entry->add($key);
	while (my ($sub_key, $sub_value) = each (%{$self->{$key}})) {
	  $node->add($sub_key, $sub_value);
	};
      }

      # Plural attributes
      elsif ($key =~ $PLURAL_RE) {
	foreach my $sub_node (@{$self->{$key}}) {
	  if ((ref $sub_node) eq 'HASH') {
	    my $node = $entry->add($key);
	    while (my ($sub_key, $sub_value) = each (%{$sub_node})) {

	      # Can contain newlines
	      if ($sub_key =~ $FORMATTED_RE) {
		$node->add($sub_key => {-type => 'raw'} =>
			     '<![CDATA['.$sub_value.']]>');
	      }

	      # Cannot contain newlines
	      else {
		$node->add($sub_key, $sub_value);
	      };
	    };
	  }
	  else {
	    $entry->add($key, $sub_node);
	  };
	};
      };
    };
  };

  return $entry;
};

# Return JSON document
sub to_json {
  return Mojo::JSON->new->encode( shift->_json );
};

# Return cleaned hash
sub _json {
  # Only allow fine first values
  my %hash;
  foreach my $key (keys %{ $_[0] }) {
    if ($key =~ $VALID_RE) {
      $hash{$key} = $_[0]->{$key};
    };
  };
  return \%hash;
};

1;

__END__

=pod

=head1 NAME

Mojolicious::Plugin::PortableContacts::Entry

=head1 SYNOPSIS

  my $res = { id => 15,
              name => {
                givenName  => 'Bender',
                familyName => 'Rodriguez'
            }};

  my $entry =
       Mojolicious::Plugin::PortableContacts::Entry->new($res);

  print $entry->to_xml;

=head1 DESCRIPTION

L<Mojolicious::Plugin::PortableContacts::Entry> is the object class
of entries for L<Mojolicious::Plugin::PortableContacts::Response>.

=head1 METHODS

=head2 C<to_json>

  my $entry = $entry->to_json;

Returns a JSON string representing the entry.
The entry will contain only valid keys.

=head2 C<to_xml>

  my $entry = $entry->to_xml;

Returns an XML string representing the entry.
The entry will contain only valid keys.

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
