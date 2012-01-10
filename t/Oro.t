use Test::More tests => 112;
use File::Temp qw/:POSIX/;
use Data::Dumper 'Dumper';
use strict;
use warnings;

$|++;

use lib '../lib';
use_ok 'Sojolicious::Oro';

my $db_file = tmpnam();

END {
  unlink $db_file;
};

my $oro = Sojolicious::Oro->new(
  $db_file => sub {
    shift->do('CREATE TABLE Name (
                 id             INTEGER PRIMARY KEY,
                 prename        TEXT NOT NULL,
                 surname        TEXT
              )');
  });

ok($oro, 'Created');
ok($oro->created, 'Created');

if ($oro->created) {
  $oro->do(
    'CREATE TABLE Content (
       id            INTEGER PRIMARY KEY,
       content       TEXT,
       title         TEXT
     )'
  );
};

ok($oro->insert(Content => { title => 'Check!',
			     content => 'This is content.'}), 'Insert');
{
  local $SIG{__WARN__} = sub {};
  ok(!$oro->insert(Content_unknown => {title => 'Hey!'}), 'Insert');
};

ok($oro->insert(Name => { prename => 'Akron',
			  surname => 'Sojolicious'}), 'Insert');

{
  local $SIG{__WARN__} = sub {};
  ok(!$oro->insert(Name => { surname => 'Rodriguez'}), 'Insert');
};

ok($oro->update(Content =>
		  { content => 'This is changed content.' } =>
		    { title => 'Check!' }), 'Update');

is($oro->last_insert_id, 1, 'Row id');

ok(!$oro->update(Content =>
		  { content => 'This is changed content.' } =>
		    { title => 'Check not existent!' }), 'Update');

{
  local $SIG{__WARN__} = sub {};
  ok(!$oro->update(Content_unknown =>
		     { content => 'This is changed content.' } =>
		       { title => 'Check not existent!' }), 'Update');

  ok(!$oro->update(Content =>
		     { content_unkown => 'This is changed content.' } =>
		       { title => 'Check not existent!' }), 'Update');
};

my $row;
ok($row = $oro->load(Content => { title => 'Check!' }), 'Load');

is ($row->{content}, 'This is changed content.', 'load');

ok($oro->insert(Content =>
		  { title => 'Another check!',
		    content => 'This is second content.' }), 'Insert');

ok($oro->insert(Content =>
		  { title => 'Check!',
		    content => 'This is third content.' }), 'Insert');

my $array;
ok($array = $oro->select(Content => { title => 'Check!' }), 'Select');
is($array->[0]->{content}, 'This is changed content.', 'Select');
is($array->[1]->{content}, 'This is third content.', 'Select');

ok($row = $oro->load(Content => { title => 'Another check!' } ), 'Load');
is($row->{content}, 'This is second content.', 'Check');

is($oro->delete(Content => { title => 'Another check!' }), 1, 'Delete');
ok(!$oro->delete(Content => { title => 'Well.' }), 'Delete');

{
  local $SIG{__WARN__} = sub {};
  ok(!$oro->select('Content_2'), 'Select');
};

$oro->select('Content' => sub {
	       like(shift->{content},
		    qr/This is (?:changed|third) content\./,
		    'Select');
	     });

my $once = 1;
$oro->select('Content' => sub {
	       ok($once--, 'Select Once');
	       like(shift->{content},
		    qr/This is (?:changed|third) content\./,
		    'Select Once');
	       return -1;
	     });

$oro->select('Name' => ['prename'] =>
	       sub {
		 ok(!exists $_[0]->{surname}, 'Fields');
		 ok($_[0]->{prename}, 'Fields');
	     });

ok($oro->update( Content =>
		   { content => 'Das ist der vierte content.' } =>
		     { 'title' => 'Check!' }), # Changes two entries!
   'Merge');

ok($oro->merge( Content =>
		  { content => 'Das ist der fuenfte content.' } =>
		    { 'title' => 'Noch ein Check!' }),
   'Merge');

ok($oro->merge( Content =>
		  { content => 'Das ist der sechste content.' } =>
		    { 'title' => ['Noch ein Check!', 'FooBar'] }),
   'Merge');

is($oro->select('Content' =>
		  { content => 'Das ist der sechste content.'}
		)->[0]->{title}, 'Noch ein Check!', 'Title');

ok($oro->merge( Content =>
		  { content => 'Das ist der siebte content.' } =>
		    { 'title' => ['HelloWorld', 'FooBar'] }),
   'Merge');

ok(!$oro->select('Content' =>
		   { content => 'Das ist der siebte content.'}
		 )->[0]->{title}, 'Title');


ok($oro->delete('Content' => { content => ['Das ist der siebte content.']}),
   'Delete');

is($oro->last_insert_id, 5, 'Row id');


{
  local $SIG{__WARN__} = sub {};
  ok(!$oro->merge( Content_unknown =>
		     { content => 'Das ist der fuenfte content.' } =>
		       { 'title' => 'Noch ein Check!' }),
     'Merge');
};

ok($oro->insert(Content => [qw/title content/] =>
	   ['CheckBulk','Das ist der sechste content'],
	   ['CheckBulk','Das ist der siebte content'],
	   ['CheckBulk','Das ist der achte content'],
	   ['CheckBulk','Das ist der neunte content'],
	   ['CheckBulk','Das ist der zehnte content']), 'Bulk Insert');

{
  local $SIG{__WARN__} = sub {};
  ok(!$oro->insert(Content => [qw/titles content/] =>
		     ['CheckBulk','Das ist der elfte content']),
     'Bulk Insert');

  ok(!$oro->insert(Content => [qw/title content/] =>
		     ['CheckBulk','Das ist der zwoelfte content', 'Yeah']),
     'Bulk Insert');

  ok(!$oro->insert(Content => [qw/title content/]), 'Bulk Insert');
};

ok($array = $oro->select('Content' => [qw/title content/]), 'Select');
is(@$array, 8, 'Check Select');

ok($array = $oro->load('Content' => {content => 'Das ist der achte content'}), 'Load');
is($array->{title}, 'CheckBulk', 'Check Select');

ok($oro->delete('Content', { title => 'CheckBulk'}), 'Delete Table');

ok($array = $oro->select('Content' => [qw/title content/]), 'Select');
is(@$array, 3, 'Check Select');

ok($array = $oro->select('Content' => ['id'] => { id => [1..4] }), 'Select');
is('134', join('', map($_->{id}, @$array)), 'Where In');


my ($rv, $sth) = $oro->prep_and_exec('SELECT count("*") as count FROM Content');
ok($rv, 'Prep and Execute');
is($sth->fetchrow_arrayref->[0], 3, 'Prep and exec');

$sth->finish;

ok($oro->dbh->{AutoCommit}, 'Transaction');
$oro->dbh->begin_work;
ok(!$oro->dbh->{AutoCommit}, 'Transaction');

foreach my $x (1..10) {
  $oro->insert(Content => { title => 'Transaction',
			    content => 'Das ist der '.$x.'. Eintrag'});
};

ok(!$oro->dbh->{AutoCommit}, 'Transaction');
$oro->dbh->commit;
ok($oro->dbh->{AutoCommit}, 'Transaction');

($rv, $sth) = $oro->prep_and_exec('SELECT count("*") as count FROM Content');
ok($rv, 'Prep and Execute');
is($sth->fetchrow_arrayref->[0], 13, 'Fetch row.');
$sth->finish;

ok($oro->dbh->{AutoCommit}, 'Transaction');
$oro->dbh->begin_work;
ok(!$oro->dbh->{AutoCommit}, 'Transaction');

foreach my $x (1..10) {
  $oro->insert(Content => { title => 'Transaction',
			    content => 'Das ist der '.$x.'. Eintrag'});
};

ok(!$oro->dbh->{AutoCommit}, 'Transaction');
$oro->dbh->rollback;
ok($oro->dbh->{AutoCommit}, 'Transaction');

($rv, $sth) = $oro->prep_and_exec('SELECT count("*") as count FROM Content');
ok($rv, 'Prep and Execute');
is($sth->fetchrow_arrayref->[0], 13, 'Fetch row.');
$sth->finish;

is($oro->count('Content'), 13, 'count');

my $load = $oro->load('Content' => ['count(*):number']);
is($load->{number}, 13, 'AS feature');

ok($oro->txn(
  sub {
    foreach (1..100) {
      $oro->insert(Content => { title => 'Check'.$_ });
    };
    return 1;
  }), 'Transaction');

is($oro->count('Content'), 113, 'Count');

ok(!$oro->txn(
  sub {
    foreach (1..100) {
      $oro->insert(Content => { title => 'Check'.$_ });
      return -1 if $_ == 50;
    };
    return 1;
  }), 'Transaction');

is($oro->count('Content'), 113, 'Count');

# Nested transactions:

ok($oro->txn(
  sub {
    my $val = 1;

    foreach (1..100) {
      $oro->insert(Content => { title => 'Check'.$val++ });
    };

    ok(!$oro->txn(
      sub {
	foreach (1..100) {
	  $oro->insert(Content => { title => 'Check'.$val++ });
	  return -1 if $_ == 50;
	};
      }), 'Nested Transaction 1');

    ok($oro->txn(
      sub {
	foreach (1..100) {
	  $oro->insert(Content => { title => 'Check'.$val++ });
	};
	return 1;
      }), 'Nested Transaction 2');

    return 1;
  }), 'Transaction');

is($oro->count('Content'), 313, 'Count');


# Less than 500
my @massive_bulk;
foreach (1..450) {
  push(@massive_bulk, ['MassiveBulk', 'Content '.$_ ]);
};

ok($oro->insert(Content => [qw/title content/] => @massive_bulk), 'Bulk Insert');

is($oro->count(Content => {title => 'MassiveBulk'}), 450, 'Bulk Check');

# More than 500
@massive_bulk = ();
foreach (1..4500) {
  push(@massive_bulk, ['MassiveBulk', 'Content '.$_ ]);
};

ok($oro->insert(Content => [qw/title content/] => @massive_bulk), 'Bulk Insert 2');

is($oro->count(Content => {title => 'MassiveBulk'}), 4950, 'Bulk Check 2');

is($oro->count('Content'), 5263, 'Count');

is($oro->delete('Content'), 5263, 'Delete all');

is($oro->count('Content'), 0, 'Count');

my ($content, $name);
ok($content = $oro->table('Content'), 'Content');
ok($name = $oro->table('Name'), 'Name');

is($content->insert({ title => 'New Content'}), 1, 'Insert with table');
is($name->insert({
  prename => 'Akron',
  surname => 'Fuxfell'
}),1 , 'Insert with table');

is($name->update({
  surname => 'Sojolicious'
},{
  prename => 'Akron',
}), 2, 'Update with table');

is($name->update({
  surname => 'Sojolicious'
},{
  prename => 'Akron',
}), 2, 'Update with table');

is(@{$name->select({ prename => 'Akron' })}, 2, 'Select with Table');

ok($name->delete({
  id => 1
}), 'Delete with Table');

ok(!$name->load({ id => 1 }), 'Load with Table');

ok($name->merge(
  { prename => 'Akron' },
  { surname => 'Sojolicious' }
), 'Merge with Table');

is($content->insert({ title => 'New Content 2'}), 1, 'Insert with table');
is($content->count, 2, 'Count with Table');

is($content->insert({ title => 'New Content 3'}), 1, 'Insert with table');

is_deeply($content->select(
  ['title'] => {
    -order => '-title',
  }), [
    { title => 'New Content 3' },
    { title => 'New Content 2' },
    { title => 'New Content' }
  ], 'Offset restriction');

is_deeply($content->select(
  ['title'] => {
    -order => '-title',
    -limit => 2
  }), [
    { title => 'New Content 3' },
    { title => 'New Content 2' }
  ], 'Limit restriction');

is_deeply($content->select(
  ['title'] => {
    -order => '-title',
    -limit => 2,
    -offset => 1
  }), [
    { title => 'New Content 2' },
    { title => 'New Content' }
  ], 'Order restriction');

ok($content->update({ content => 'abc' } => {title => 'New Content'}), 'Update');;
ok($content->update({ content => 'cde' } => {title => 'New Content 2'}), 'Update');
ok($content->insert({ content => 'cdf',  title => 'New Content 1'}),'Insert');;
ok($content->update({ content => 'efg' } => {title => 'New Content 2'}),'Update');;
ok($content->update({ content => 'efg' } => {title => 'New Content 3'}),'Update');

is(join(',',
	map($_->{id},
	    @{$content->select(
	      ['id'] =>
		{
		  -order => ['-content', '-title']
		}
	      )})), '3,2,4,1', 'Combined Order restriction');

ok($content->insert(
  ['title', 'content'] =>
    ['Bulk 1', 'Content'],
    ['Bulk 2', 'Content'],
    ['Bulk 3', 'Content'],
    ['Bulk 4', 'Content']), 'Bulk Insertion');


my $pager = $content->pager(
  ['id'] => {
    -order => ['-content', '-title'],
    -limit => 2
  });

my @result;
while ($_ = $pager->()) {
  push(@result, [ map { $_->{id} } @$_ ]);
};

is_deeply(\@result, [[3,2],[4,1],[8,7],[6,5]], 'Pager result');

$pager = $content->pager(
  ['id'] => {
    -order => ['-content', '-title'],
    -limit => 3,
    -offset => 1
  });

@result = ();
while ($_ = $pager->()) {
  push(@result, [ map { $_->{id} } @$_ ]);
};

is_deeply(\@result, [[2,4,1],[8,7,6],[5]], 'Pager result 2');


$pager = $content->pager(
  ['id'] => {
    -order => ['-content', '-title'],
    -limit => 3
  });

my $pager2 = $content->pager(
  ['id'] => {
    -order => ['-content', '-title'],
    -limit => 3,
    -offset => 1
  }
);

@result = ();
while ($_ = $pager->()) {
  push(@result, [ map { $_->{id} } @$_ ]);
  if ($_ = $pager2->()) {
    push(@result, [ map { $_->{id} } @$_ ]);
  };
};

is_deeply(\@result,
	  [[3,2,4],[2,4,1],[1,8,7],[8,7,6],[6,5],[5]],
	  'Pager result 3');

$pager = $content->pager(['id'], { -order => 'id' } );

my $i = 1;
@result = ();
while ($_ = $pager->($i++)) {
  push(@result, [ map { $_->{id} } @$_ ] );
};

is_deeply(\@result,
	  [[1],[2,3],[4,5,6],[7,8]], 'Pager result 4');

ok($oro->dbh->disconnect, 'Disonnect');

ok($oro->insert(Content => { title => 'Test', content => 'Value'}), 'Reconnect');


__END__
