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
MY_API my_obj *func(ctx *ctx, const char *path);
END
  }

  if (-f $file) {
    my $converter = Convert::H::XS->new;
    $converter->process($file);

    eq_or_diff $converter->{stash}{function} => {
      func => [
        'MY_API my_obj *',
        [
          'ctx *ctx',
          'const char *path',
        ],
      ],
    }, 'got correct function info';
  }
}


done_testing;
