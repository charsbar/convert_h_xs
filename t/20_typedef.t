use strict;
use warnings;
use Test::More;
use Test::Differences;
use Convert::H::XS;
use File::Temp;

{
  my $dir = File::Temp->newdir;
  my $file = "$dir/foo.h";
  {
    open my $fh, ">", $file;
    print $fh <<"END";
typedef unsigned int my_id;
typedef bar *func(obj *obj, int var);
END
  }

  if (-f $file) {
    my $converter = Convert::H::XS->new;
    $converter->process($file);

    eq_or_diff $converter->{stash}{typedef} => {
      'my_id' => 'unsigned int',
      '*func(obj *obj, int var)' => 'bar',
    }, 'got correct typedef info';
  }
}


done_testing;
