package Mojolicious::Plugin::PortableContacts::Entry;
use Mojo::Base -base;
use Mojolicious::Plugin::XML::Base;

# Todo: Allow further valid labels
# Todo: Use Mojo::JSON true/false for 'connected'

our $SINGULAR_RE = qr/^(?:id|
                       (?:preferredUsern|nickn|displayN)?ame|
                       published|
                       updated|
                       birthday|
                       anniversary|
                       gender|
                       note|
                       utcOffset|
                       connected)$/x;

our $PLURAL_RE = qr/^(?:email|
                      url|
                      phoneNumber|
                      im|
                      photo|
                      tag|
                      relationship|
                      organization|
                      addresse|
                      account)s$/x;

our $VALID_RE = qr(^$SINGULAR_RE|$PLURAL_RE$);

our $FORMATTED_RE = qr/^(?:formatted|streetAddress|description)$/;


# Return XML document
sub to_xml {
  return shift->_xml->to_pretty_xml;
};


# Return JSON document
sub to_json {
  return Mojo::JSON->new->encode( shift->_json );
};


# Return cleaned XML serialized object
sub _xml {
  my $self = shift;

  # New XML object
  my $entry = Mojolicious::Plugin::XML::Base->new('entry');

  foreach my $key (keys %$self) {

    # Normal attributes
    if (!ref $self->{$key} && $key =~ $SINGULAR_RE) {

      # Is no note
      unless ($key eq 'note') {
	$entry->add($key => $self->{$key});
      }

      # Is a note
      else {
	$entry->add($key =>
		      {-type => 'raw'} =>
			'<![CDATA['.$self->{$key}.']]>');
      };
    }

    # Complex attributes
    else {

      # Singular value
      if (ref($self->{$key}) eq 'HASH'  && $key =~ $SINGULAR_RE) {
	my $node = $entry->add($key);

	while (my ($sub_k, $sub_v) = each (%{$self->{$key}})) {
	  $node->add($sub_k, $sub_v);
	};
      }

      # Plural attributes
      elsif ($key =~ $PLURAL_RE) {
	foreach my $sub_node (@{ $self->{$key} }) {

	  # Complex sub attribute
	  if ((ref $sub_node) eq 'HASH') {
	    my $node = $entry->add($key);
	    while (my ($sub_k, $sub_v) = each (%{$sub_node})) {

	      # Can contain newlines
	      if ($sub_k =~ $FORMATTED_RE) {
		$node->add($sub_k =>
			     {-type => 'raw'} =>
			       '<![CDATA[' . $sub_v . ']]>');
	      }

	      # Cannot contain newlines
	      else {
		$node->add($sub_k, $sub_v);
	      };
	    };
	  }

	  # Simple sub attribute
	  else {
	    $entry->add($key, $sub_node);
	  };
	};
      };
    };
  };

  # Return entry object
  $entry;
};


# Return cleaned hash
sub _json {
  my %hash;

  # Only allow fine first values
  foreach my $key (keys %{ $_[0] }) {
    $hash{$key} = $_[0]->{$key} if $key =~ $VALID_RE;
  };

  # Return new hash
  \%hash;
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

Copyright (C) 2011-2012, Nils Diewald.

This program is free software, you can redistribute it
and/or modify it under the same terms as Perl.

=cut
