#!/usr/bin/env perl
# $Id: texindy,v 1.13 2011/01/18 22:18:29 jschrod Exp $
#------------------------------------------------------------
# (history at end)

=head1 NAME

texindy - create sorted and tagged index from raw LaTeX index

=head1 SYNOPSIS

 texindy [-V?h] [-qv] [-iglr] [-d magic] [-o outfile.ind] [-t log] \
         [-L lang] [-C codepage] [-M module] [idx0 idx1 ...]

=head2 GNU-Style Long Options for Short Options:

 -V / --version
 -? / -h / --help
 -q / --quiet
 -v / --verbose
 -i / --stdin
 -g / --german
 -l / --letter-ordering
 -r / --no-ranges
 -d / --debug          (multiple times)
 -o / --out-file
 -t / --log-file
 -L / --language
 -C / --codepage
 -M / --module         (multiple times)
 -I / --input-markup   (supported: latex, xelatex, omega)


=head1 DESCRIPTION

B<texindy> is the LaTeX-specific command of xindy, the flexible
indexing system. It takes a raw index as input, and produces a merged,
sorted and tagged index. Merging, sorting, and tagging is controlled
by xindy modules, with a convenient set already preloaded.

Files with the raw index are passed as arguments. If no arguments are
passed, the raw index will be read from standard input.

A good introductionary description of B<texindy> appears in the
indexing chapter of the LaTeX Companion (2nd ed.)

If you want to produce an index for LaTeX documents with special index
markup, the command xindy(1) is probably more of interest for you.

B<texindy> is an approach to merge support for the I<make-rules>
framework, own xindy modules (e.g., for special LaTeX commands in the
index), and a reasonable level of MakeIndex compatibility.


=head1 OPTIONS

=over

=item C<--version> / B<-V>

output version numbers of all relevant components and exit.

=item C<--help> / B<-h> / B<-?>

output usage message with options explanation.

=item C<--quiet> / B<-q>

Don't output progress messages. Output only error messages.

=item C<--verbose> / B<-v>

Output verbose progress messages.

=item C<--debug> I<magic> / B<-d> I<magic>

Output debug messages, this option may be specified multiple times.
I<magic> determines what is output:

 magic          remark
 ------------------------------------------------------------
 script         internal progress messages of driver scripts
 keep_tmpfiles  don't discard temporary files
 markup         output markup trace, as explained in xindy manual
 level=n        log level, n is 0 (default), 1, 2, or 3

=item C<--out-file> F<outfile.ind> / B<-o> F<outfile.ind>

Output index to file F<outfile.ind>. If this option is not passed, the
name of the output file is the base name of the first argument and the
file extension F<ind>. If the raw index is read from standard input,
this option is mandatory.

=item C<--log-file> F<log.ilg> / B<-t> F<log.ilg>

Output log messages to file F<log.ilg>. These log messages are
independent from the progress messages that you can influence with
C<--debug> or C<--verbose>.

=item C<--language> I<lang> / B<-L> I<lang>

The index is sorted according to the rules of language I<lang>. These
rules are encoded in a xindy module created by I<make-rules>.

If no input encoding is specified via C<--codepage> or enforced by
input markup, a xindy module for that language is searched with a
latin, a cp, an iso, ascii, or utf8 encoding, in that order.

=item C<--codepage> I<enc> / B<-C> I<enc>

There are two different situations and use cases for this option.

=over

=item 1.

Input markup is C<latex> (the default).

Then B<texindy>'s raw input is assumed to be encoded in LaTeX Internal
Character Representation (LICR). I.e., non-ASCII characters are
encoded as command sequences. This option tells xindy the encoding it
shall use for letter group headings. (Additionally it specifies the
encoding used internally for sorting -- but that doesn't matter for
the result.)

Only LICR encodings for Latin script alphabets are supported; more
precisely characters that are in LaTeX latin1, latin2, and latin3 LICR
encodings.

Even when you specify C<utf8> as codepage, only these characters will
be known. But if you use non-Latin alphabets, you probably use (or
should use) XeLaTeX or LuaLaTeX and then you have a different input
markup.

=item 2.

Input markup is C<xelatex> or C<omega>.

Then this option is ignored; codepage C<utf8> is enforced.

B<texindy>'s raw input is assumed to be UTF-8 encoded, LICR is not
used.

=back

=item C<--module> I<module> / B<-M> I<module>

Load the xindy module F<module.xdy>. This option may be specified
multiple times. The modules are searched in the xindy search path that
can be changed with the environment variable C<XINDY_SEARCHPATH>.

=item C<--input-markup> I<input> / B<-I> I<input>

Specifies the input markup of the raw index. Supported values for
I<input> are C<latex>, C<xelatex>, and C<omega>.

C<latex> input markup is the one that is emitted by default from the
LaTeX kernel, or by the C<index> macro package of David Jones, when
used with standard LaTeX or pdfLaTeX. ^^-notation of single byte
characters is supported. Usage of LaTeX's I<inputenc> package is
assumed as well, i.e., raw input is encoded in LICR.

C<xelatex> input markup is like C<latex>, but without I<inputenc>
usage. Raw input is encoded in UTF-8. LuaLaTeX has the same input
markup, there's no special option value for it.

C<omega> input markup is like C<latex> input markup, but with Omega's
^^-notation as encoding for non-ASCII characters. LICR encoding is not
used then, and C<utf8> is enforced to be the codepage for sorting and
for output of letter group headings.

=back


=head1 SUPPORTED LANGUAGES / CODEPAGES

The following languages are supported:

=head2 Latin scripts

 albanian      gypsy             portuguese
 croatian      hausa		 romanian
 czech	       hungarian 	 russian-iso
 danish	       icelandic	 slovak-small
 english       italian		 slovak-large
 esperanto     kurdish-bedirxan  slovenian
 estonian      kurdish-turkish	 spanish-modern
 finnish       latin		 spanish-traditional
 french	       latvian		 swedish
 general       lithuanian	 turkish
 german-din    lower-sorbian	 upper-sorbian
 german-duden  norwegian	 vietnamese
 greek-iso     polish

German recognizes two different sorting schemes to handle umlauts:
normally, C<�> is sorted like C<ae>, but in phone books or
dictionaries, it is sorted like C<a>. The first scheme is known as
I<DIN order>, the second as I<Duden order>.

C<*-iso> language names assume that the raw index entries are in ISO
8859-9 encoding.

C<gypsy> is a northern Russian dialect.

=head2 Cyrillic scripts

 belarusian    mongolian  	 serbian
 bulgarian     russian    	 ukrainian
 macedonian

=head2 Other scripts

 greek         klingon

=head2 Available Codepages

This is not yet written. You can look them up in your xindy
distribution, in the F<modules/lang/language/> directory (where
I<language> is your language). They are named
F<variant-codepage-lang.xdy>, where F<variant-> is most often empty
(for german, it's C<din5007> and C<duden>; for spanish, it's C<modern>
and C<traditional>, etc.)

 < Describe available codepages for each language >

 < Describe relevance of codepages (as internal representation) for
   LaTeX inputenc >


=head1 TEXINDY STANDARD MODULES

There is a set of B<texindy> standard modules that help to process
LaTeX index files. Some of them are automatically loaded. Some of them
are loaded by default, this can be turned off with a B<texindy>
option. Others may be specified as C<--module> argument to achieve a
specific effect.

 xindy Module    Category  Description

=head2 Sorting

 word-order      Default   A space comes before any letter in the
                           alphabet: ``index style'' is listed before
                           ``indexing''. Turn it off with option -l.
 letter-order    Add-on    Spaces are ignored: ``index style''
                           is sorted after ``indexing''.
 keep-blanks     Add-on    Leading and trailing white space (blanks
                           and tabs) are not ignored; intermediate
                           white space is not changed.
 ignore-hyphen   Add-on    Hyphens are ignored:
			   ``ad-hoc'' is sorted as ``adhoc''.
 ignore-punctuation Add-on All kinds of punctuation characters are
			   ignored: hyphens, periods, commas, slashes,
			   parentheses, and so on.
 numeric-sort    Auto      Numbers are sorted numerically, not like
			   characters: ``V64'' appears before ``V128''.

=head2 Page Numbers

 page-ranges     Default   Appearances on more than two consecutive
			   pages are listed as a range: ``1--4''.
			   Turn it off with option -r.
 ff-ranges       Add-on    Uses implicit ``ff'' notation for ranges
			   of three pages, and explicit ranges
			   thereafter: 2f, 2ff, 2--6.
 ff-ranges-only  Add-on    Uses only implicit ranges: 2f, 2ff.
 book-order      Add-on    Sorts page numbers with common book numbering
			   scheme correctly -- Roman numerals first, then
			   Arabic numbers, then others: i, 1, A.

=head2 Markup and Layout

 tex             Auto      Handles basic TeX conventions.
 latex-loc-fmts  Auto	   Provides LaTeX formatting commands
		    	   for page number encapsulation.
 latex           Auto	   Handles LaTeX conventions, both in raw
		    	   index entries and output markup; implies
		    	   tex.
 makeindex       Auto	   Emulates the default MakeIndex input syntax
			   and quoting behavior.
 latin-lettergroups Auto   Layout contains a single Latin letter
			   above each group of words starting with the
			   same letter.
 german-sty      Add-on	   Handles umlaut markup of babel's german
			   and ngerman options.


=head1 COMPATIBILITY TO MAKEINDEX

B<xindy> does not claim to be completely compatible with MakeIndex,
that would prevent some of its enhancements. That said, we strive to
deliver as much compatibility as possible. The most important
incompatibilities are

=over

=item *

For raw index entries in LaTeX syntax, C<\index{aaa|bbb}> is
interpreted differently. For MakeIndex C<bbb> is markup that is output
as a LaTeX tag for this page number. For B<xindy>, this is a location
attribute, an abstract identifier that will be later associated with
markup that should be output for that attribute.

For straight-forward usage, when C<bbb> is C<textbf> or similar, we
supply location attribute definitions that mimic MakeIndex's
behaviour.

For more complex usage, when C<bbb> is not an identifier, no such
compatibility definitions exist and may also not been created with
current B<xindy>. In particular, this means that by default the LaTeX
package C<hyperref> will create raw index files that cannot be
processed with B<xindy>. This is not a bug, this is the unfortunate
result of an intented incompatibility. It is currently not possible to
get both hyperref's index links and use B<xindy>.

A similar situation is reported to exist for the C<memoir> LaTeX
class.

Programmers who know Common Lisp and Lex and want to work on a remedy
should please contact the author.

=item *

If you have an index rage and a location attribute, e.g.,
C<\index{key\(attr}> starts the range, one needs (1) to specify that
attribute in the range closing entry as well (i.e., as
C<\index{key\)attr}>) and (2) one needs to declare the index attribute
in an B<xindy> style file.

MakeIndex will output the markup C<\attr{page1--page2}> for such a
construct. This is not possible to achieve in B<xindy>, output will be
C<\attrMarkup{page1}--\attrMarkup{page2}>. (This is actually
considered a bug, but not a high priority one.)

The difference between MakeIndex page number tags and B<xindy>
location attributes was already explained in the previous item.

=item *

The MakeIndex compatibility definitions support only the default raw
index syntax and markup definition. It is not possible to configure
raw index parsing or use a MakeIndex style file to describe output
markup.

=back



=head1 ENVIRONMENT

=over

=item C<TEXINDY_AUTO_MODULE>

This is the name of the xindy module that loads all auto-loaded
modules. The default is C<texindy>.

=back


=head1 AUTHOR

Joachim Schrod


=head1 LEGALESE

Copyright (c) 2004-2014 by Joachim Schrod.

B<texindy> is free software; you can redistribute it and/or modify it
under the terms of the GNU General Public License as published by the
Free Software Foundation; either version 2 of the License, or (at your
option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.


=for Emacs
#'

=cut


use strict;
use English qw(-no_match_vars);

our $VERSION = sprintf "%d.%02d", q$Revision: 1.13 $ =~ /: (\d+)\.(\d+)/ ;


# Used modules.

use Cwd;
use File::Basename;
use Getopt::Long qw(:config bundling);


# Determine environment. Where is our library directory, and our modules?

our $is_TL = ( 'yes' eq 'yes' );
our $is_w32 = ( $OSNAME =~ /^MSWin/i ) ;
our $real_cmd = Cwd::realpath($0);
our $cmd_dir = dirname($real_cmd);
our $cmd = basename($0);
our $xindy;

# In TeX-Live, user commands are symlinks in some bin directory, and
# the actual scripts are in the library directory and have a .pl
# extension. In standalone installations, user command xindy is
# expected to be in the same directory as our command.

if ( $is_TL ) { # TeX Live

    if ( $is_w32 ) {
	$xindy = "$cmd_dir/xindy.pl";
    } else {
	die "$cmd: not a symlink as required for TeX Live"  unless -l $0;
	# FIXME: What this good for? Ain't xindy not also
	# "$cmd_dir/xindy.pl" in a Unix TL installation? Why does
	# Peter use the directory of the last symlink, where it just
	# finds the symlink again that is then expanded by xindy.pl?
	$real_cmd = $0;
	$cmd_dir = dirname($real_cmd);
	# Follow symlinks, but remember last one
	my $lcmd_dir;
	while ( -l $real_cmd ) {
	    $lcmd_dir = $cmd_dir;
	    $real_cmd = readlink($real_cmd);
	    $real_cmd = "$lcmd_dir/$real_cmd"  unless $real_cmd =~ m,^[\\/],; # relative link
	    $cmd_dir = dirname($real_cmd);
	}
	$xindy = "$lcmd_dir/xindy";
    }
    # FIXME: That's a very ugly kludge to achieve that the VERSION
    # file is found in output_xindy_release(). The real solution is to
    # copy the code from xindy.pl that determines $modules_dir and
    # $lib_dir and use that code as well.
    $cmd_dir = Cwd::realpath("$cmd_dir/../../xindy/modules");
    die "Cannot locate xindy modules directory"  unless -f "$cmd_dir/../VERSION";
} else {
    if ( -f "$cmd_dir/xindy" && -x _ ) {
	$xindy = "$cmd_dir/xindy";
    } elsif ( -f "$cmd_dir/xindy.pl" && -x _ ) {
	$xindy = "$cmd_dir/xindy.pl";
    } else {
	die "$cmd: cannot locate xindy\n";
    }
}
die "$cmd: cannot locate xindy\n"  unless -f $xindy && ($is_w32 || -x $xindy);


# Check arguments, store them in proper variables.

sub usage ( ;$ )
{
    my $exit_code = shift;
    $exit_code += 0;			# turn undef into 0
    my $out = ( $exit_code ? *STDERR : *STDOUT );
    print $out <<_EOT_

usage: $cmd [-V?h] [-qv] [-iglr] [-d magic] [-o outfile.ind] [-t log] \\
            [-L lang] [-C codepage] [-M module] [-I input] [idx0 idx1 ...]

GNU-STYLE LONG OPTIONS FOR SHORT OPTIONS:

 -V / --version
 -? / -h / --help
 -q / --quiet
 -v / --verbose
 -i / --stdin
 -g / --german
 -l / --letter-ordering
 -r / --no-ranges
 -d / --debug          (multiple times)
                       (supported: script, keep_tmpfiles, markup, level=n)
 -o / --out-file
 -t / --log-file
 -L / --language
 -C / --codepage
 -M / --module         (multiple times)
 -I / --input-markup   (supported: latex, omega)

_EOT_
  ;
    exit ($exit_code);
}

our ($output_version, $quiet, $verbose, $stdin, @debug,
     $outfile, $logfile, $language, $codepage, @modules, $input_markup);
$language = 'general';
$codepage = 'latin';
$input_markup = 'latex';

parse_options();
output_version()  if $output_version;	# will not return
usage(1)  if ( ! $stdin && @ARGV == 0 ); # brain damaged, but like makeindex


# Construct xindy options, and eventually switch to it.

my @opt;
push (@opt, '-q')  if $quiet;
push (@opt, '-v')  if $verbose;
push (@opt, map { ('-d', $_) } @debug)  if @debug;
push (@opt, '-o', $outfile)  if $outfile;
push (@opt, '-t', $logfile)  if $logfile;
push (@opt, '-L', $language);
push (@opt, '-C', $codepage)  if $codepage;
push (@opt, '-M', "tex/inputenc/$codepage")  if $codepage;
push (@opt, map { ('-M', $_) } ($ENV{TEXINDY_AUTO_MODULE} || 'texindy',
				@modules));
push (@opt, '-I', $input_markup);

print "Calling xindy as: $xindy @opt @ARGV\n"  if (grep /^script$/, @debug);
exec_xindy(@opt, @ARGV);

# NOT REACHED


# ------------------------------------------------------------


sub exec_xindy {
    if ( $is_w32 ) {
	system ($EXECUTABLE_NAME, $xindy, @_);
	if ($? == -1) {
	    die "$cmd: could not execute xindy: $ERRNO\n";
	} elsif ($? & 127) {
	    die "xindy died with signal " . ($? & 127) ."\n";
	} else {
	    exit ($? >> 8);
	}
    } else {
	exec ($xindy, @_);
	die "$cmd: could not execute xindy: $!\n";
    }
}


sub parse_options() {

    my ($german, $letter_ordering, $no_ranges);
    GetOptions(
	       'version|V'          => \$output_version,
	       'help|h|?'           => \&usage,
	       'quiet|q'            => \$quiet,
	       'verbose|v'          => \$verbose,
	       'stdin|i'            => \$stdin,
	       'german|g'           => \$german,
	       'letter-ordering|l'  => \$letter_ordering,
	       'no-ranges|r'        => \$no_ranges,
	       'debug|d=s'          => \@debug,
	       'out-file|o=s'       => \$outfile,
	       'log-file|t=s'       => \$logfile,
	       'language|L=s'       => \$language,
	       'codepage|C=s'       => \$codepage,
	       'module|M=s'         => \@modules,
	       'input-markup|I=s'   => \$input_markup,
	      )
      or  usage(1);

    if ( $german ) {
	unshift (@modules, 'german-sty');
	if ( $language eq 'general' ) {
	    $language = 'german-din';
	} elsif ( $language !~ /^german/ ) {
	    print STDERR "You cannot specify -g and -L at the same time.\n";
	    #print STDERR "NOTE: -g is obsolete anyhow.\n";
	    exit (1);
	}
    }
    unshift (@modules, ($letter_ordering ? 'letter-order' : 'word-order'));
    unshift (@modules, 'page-ranges')  unless $no_ranges;

    # Check that the input markup is known. xelatex and omega markup implies
    # codepage utf8 for sorting, but no inputenc. We set the codepage
    # to undef to prevent loading of the inputenc module. Setting it
    # to utf8 for sort encoding is done by the xindy script.
    if ( $input_markup ne 'latex'  &&  $input_markup ne 'xelatex'  &&
	 $input_markup ne 'omega' ) {
	print STDERR "Unsupported input markup $input_markup.\n";
	usage(1);
    }
    if ( $input_markup eq 'xelatex'  ||  $input_markup eq 'omega' ) {
	$codepage = undef;
    }

}


sub output_version () {
    output_xindy_release();
    print "$cmd script version: $VERSION\n";
    my @xindy_cmd = ('--internal-version');
    push (@xindy_cmd, qw(-d script --foobar))  if grep(/^script$/, @debug);
    exec_xindy(@xindy_cmd);
}


sub output_xindy_release () {
    my $version = 'unknown';
    my $version_file;
    if ( -f "$cmd_dir/../VERSION" ) {
	$version_file = "$cmd_dir/../VERSION";
    } else {
	# Where is the library directory?
	my $lib_dir;
	if ( $ENV{XINDY_LIBDIR} ) {
	    $lib_dir = $ENV{XINDY_LIBDIR};
	} elsif ( '@libdir@' ne '@libdir' . '@' ) { # GNU configure at work?
	    if ( -d '@libdir@/xindy' ) { # /usr style
		$lib_dir = '@libdir@/xindy';
	    } else {
		$lib_dir = '@libdir@'; # /opt style
	    }
	} elsif ( -f "$cmd_dir/../lib/xindy.run" ) { # /opt style
	    $lib_dir = "$cmd_dir/../lib";
	} elsif ( -d "$cmd_dir/../lib/xindy" ) { # /usr style
	    $lib_dir = "$cmd_dir/../lib/xindy";
	} else {
	    die "Cannot locate xindy library directory";
	}
	if ( -f "$lib_dir/VERSION" ) {
	    $version_file = "$lib_dir/VERSION";
	}
    }

    if ( $version_file ) {
	if ( open(VERSION, "<$version_file") ) {
	    while ( $version = <VERSION> ) {
		chomp ($version);
		$version =~ s/\#.*// ;
		$version =~ s/^\s+// ;
		$version =~ s/\s+$// ;
		last  if $version;
	    }
	    close (VERSION);
	}
    }
    print "xindy release: $version\n";
}



#======================================================================
#
# $Log: texindy,v $
# Revision 1.13  2011/01/18 22:18:29  jschrod
#     Document the range raw markup incompatibility with MakeIndex.
# (Bug ticket 998541)
#
# Revision 1.12  2010/08/12 00:16:01  jschrod
#     Output help message on stdout if there's no error.
#
# Revision 1.11  2010/05/10 23:39:24  jschrod
#     Incorporate TeX-Live patches from Vladimir Volovich and Peter
# Breitenlohner: Support for TL installation scheme, support for Mac OS
# X, support for Windows in TL.
#
# Revision 1.10  2010/04/20 00:15:23  jschrod
#     Emphasize incompatibility with hyperref in man page.
#
# Revision 1.9  2009/12/03 00:28:22  jschrod
#     Search perl via env.
#
# Revision 1.8  2009/03/22 11:08:18  jschrod
#     man page: --v is --verbose, not --version.
#
# Revision 1.7  2009/03/21 16:32:06  jschrod
#     Inputenc merge rules must be loaded before other texindy modules;
# otherwise inputenc markup would be discarded by tex.xdy.
#
# Revision 1.6  2008/02/17 14:55:32  jschrod
#     Use exitcode 0 when usage is explicitly demanded with --help et.al.
#
# Revision 1.5  2006/07/30 10:30:42  jschrod
#     Check if an exec() error happened and output an error message.
# (Ticket 1230801)
#
# Revision 1.4  2006/07/19 00:29:56  jschrod
#     Support for omega input markup.
#
# Revision 1.3  2004/11/01 22:48:51  jschrod
#     Locate xindy script.
#     Terminate on option error.
#     Fix up version output.
#
# Revision 1.2  2004/05/26 21:30:11  jschrod
#     Added POD documentation.
#
# Revision 1.1  2004/05/24 19:47:13  jschrod
#     Introduce new driver script, as part of the "Companion Release".
#
