package Mojolicious::Plugin::PortableContacts::Entry;
use strict;
use warnings;

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

sub new {
    my $class = shift;
    my $self = shift;
    bless $self, $class;
};

sub to_xml {
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

# Return as JSON string
sub to_json {
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

sub parse {
    my $self = shift;
    # json or xml or hash_refxs
    my $object = shift;

    return $self = bless $object, ref($self);
};



__END__

sub get {
    my $self = shift;
    my $key = shift;

    # singular attribute
    if ($key =~ $SINGULAR_RE) {
	return $self->{$key};
    }

    # plural attribute
    elsif ($key =~ $PLURAL_RE) {
	my $plural = defined $self->{$key} ? $self->{$key} : [];
	return Mojolicious::Plugin::PortableContacts::User::Plural->new($plural);
    };

    warn('Unknown attribute');
    return;
};

sub connections {
    my $self = shift;
    my %conditions = @_;
    my %cond = (
	'filterBy' => '',
	'filterOp' => 'm/^(?:equals|contains|startswith|present)$/',
	'filterValue' => '',
	'updatedSince' => '',
	'sortBy' => '',
	'sortOrder' => 'm/^(?:a|de)scending$/',
	'startIndex' => 'm/^\d+$/',
	'count' => 'm/^\d+$/',
	'fields' => 'm/^(?:[a-zA-Z,\s]+|\@all)$/',
	);
};



package Mojolicious::Plugin::PortableContacts::User::Plural;
use strict;
use warnings;

sub new {
    my $class = ref($_[0]) ? ref(shift(@_)) : shift;
    my $self = shift || [];
    bless $self, $class;
};

sub where {
    my $self = shift;
    my %conditions = @_;
    my @array = @$self;

    while (my ($key, $value) = each %conditions) {
	@array = grep ($_->{$key} eq $value, @array);
    };

    return $self->new(\@array);
};


