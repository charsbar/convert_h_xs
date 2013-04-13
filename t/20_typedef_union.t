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
typedef union {
  int int_value;
  my_id id;
  void *ptr;
} my_data;
END
  }

  if (-f $file) {
    my $converter = Convert::H::XS->new;
    $converter->process($file);

    eq_or_diff $converter->{stash}{typedef_union} => {
      my_data => [
        'int int_value',
        'my_id id',
        'void *ptr',
      ],
    }, 'got correct typedef union info';
  }
}


done_testing;
