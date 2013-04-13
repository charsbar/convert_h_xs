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
#define FOO(x) ((x)->encoding)
#define BAR(x,y) \\
  ((x)->encoding = y)
END
  }

  if (-f $file) {
    my $converter = Convert::H::XS->new;
    $converter->preprocess($file);

    eq_or_diff $converter->{stash}{define_with_args} => [
      ['FOO(x)', '((x)->encoding)'],
      ['BAR(x,y)', '((x)->encoding = y)'],
    ], 'got correct #define info';
  }
}


done_testing;
