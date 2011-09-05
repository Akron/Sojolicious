package Mojolicious::Plugin::PortableContacts::Entry;
use Mojo::Base -base;
use Mojolicious::Plugin::XML::Serial;

use Exporter 'import';
#our @EXPORT_OK = ('SINGULAR_RE',
#		  'PLURAL_RE',
#		  'VALID_RE',
#		  'FORMATTED_RE');

# todo - allow further valid labels

our ($SINGULAR_RE, $PLURAL_RE, $VALID_RE, $FORMATTED_RE);
BEGIN {
    our $SINGULAR_RE = qr/^(?:id|
                             (?:preferred_user|nick|display_)?name|
                             published|
                             updated|
                             birthday|
                             anniversary|
                             gender|
                             note|
                             utc_offset|
                             connected)$/x;
    our $PLURAL_RE = qr/^(?:email|
                            url|
                            phone_number|
                            im|
                            photo|
                            tag|
                            relationship|
                            organization|
                            addresse|
                            account)s$/x;
    our $VALID_RE = qr(^$SINGULAR_RE|$PLURAL_RE$);
    our $FORMATTED_RE = qr/^(?:formatted|streetAddress|description)$/;
};

# Return XML document
sub to_xml {
    return shift->_xml->to_pretty_xml;
};

# Return cleaned xml serialized object
sub _xml {
    my $self = shift;

    my $entry = Mojolicious::Plugin::XML::Serial->new('entry');

    foreach my $key (keys %$self) {

	# Normal value
	if (!ref $self->{$key} && $key =~ $SINGULAR_RE) {

	    unless ($key eq 'note') {
		$entry->add($key, $self->{$key});
	    } else {
		$entry->add($key => {-type => 'raw'} =>
			   '<![CDATA['.$self->{$key}.']]>');
	    };
	}

	else {
	    if (ref($self->{$key}) eq 'HASH'  && $key =~ $SINGULAR_RE) {
		my $node = $entry->add($key);
		while (my ($sub_key, $sub_value) = each (%{$self->{$key}})) {
		    $node->add($sub_key, $sub_value);
		};
	    }

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
			my $node = $entry->add($key, $sub_node);
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
