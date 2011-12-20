use strict;
use warnings;

# Delete entry
sub delete {
  my ($self, $id) = @_;

  my $oro  = $self->{oro};
  my $name = $self->{name};

  # No id given
  return unless $id;

  # Delete entry
  return $oro->transaction(
    sub {

      # Use id array
      $id = ref($id) ? $id : [$id];

      # Delete resource from database
      if ($oro->delete($name => { res_id => $id }) > 0) {

	# Leave id for max id and uniqueness
	if ($oro->insert(
	  $name => ['res_id'] => map([$_], @$id))) {

	  # Delete resource from updated table
	  $oro->delete(
	    $name . '_UPDATED ' => {
	      res_id  => $id
	    }) or return -1;

	  return 1;
	};
      };

      # Unable to delete entry
      return -1;
    });
};

1;

__END__

# For documentation, see Sojolicious::ComplexValues.
