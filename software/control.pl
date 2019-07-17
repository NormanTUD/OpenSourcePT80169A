#!/usr/bin/perl

=head
            DO WHAT THE FUCK YOU WANT TO PUBLIC LICENSE
                    Version 2, December 2004

 Copyright (C) 2004 Sam Hocevar
  14 rue de Plaisance, 75014 Paris, France
 Everyone is permitted to copy and distribute verbatim or modified
 copies of this license document, and changing it is allowed as long
 as the name is changed.

            DO WHAT THE FUCK YOU WANT TO PUBLIC LICENSE
   TERMS AND CONDITIONS FOR COPYING, DISTRIBUTION AND MODIFICATION

  0. You just DO WHAT THE FUCK YOU WANT TO.
=cut

use strict;
use warnings;

use Term::ANSIColor;
use Data::Dumper;
use Business::ISBN;
use LWP::Simple;
use Digest::MD5 qw/md5_hex/;
use HTML::Entities;
use String::ShellQuote;
use autodie;
use JSON::Parse 'parse_json';
use Device::SerialPort qw(:PARAM :STAT 0.07);
use Time::HiRes qw/nanosleep gettimeofday/;
use Image::Magick;
use List::Util qw(sum);
use File::Copy;
use Image::Size;
use Data::Compare;
use Carp qw/cluck/;
use Proc::ProcessTable;

$SIG{CHLD} = 'IGNORE';

my $starttime = gettimeofday();

my $mainpid = $$;

sub debug (@);
sub warn_color (@);
sub warn_ok (@);
sub debug_dumper (@);

sub print_normal (@);
sub print_status (@);
sub warn_error (@);
sub print_ok (@);

my @failed = ();

my %options = (
	debug => 0,
	notify => 1,
	preprocessing => 1,
	pageturner => undef,
	language => 'deu',
	has_barcode => undef,
	author => undef,
	has_isbn => undef,
	max_page => undef,
	ocr => undef,
	autocropthreshold => 1.02,
	serial => '/dev/ttyUSB0',
	test => 0,
	max_forks => 6,
	titlepage => 0
);

my @forks = ();
my $ob = undef;

analyze_args(@ARGV);

install_needed_software();

END {
	if($mainpid == $$) {
		my $endtime = gettimeofday();
		my $elapsed = $endtime - $starttime;
		printf("TOOK %s SECONDS", humanreadabletime($elapsed));
		if($options{max_page}) {
			print ", AVG. PER PAGE: ";
			printf("%s", humanreadabletime($elapsed / $options{max_page}));
		}
		print "\n";
	}
}

if($options{test}) {
	debug "Starting test";

	my $pid = fork();
	if($pid == 0) {
		sleep 2;
		exit;
	}
	test("get_number_of_forks()", get_number_of_forks(), 1);
	wait();
	test("get_number_of_forks()", get_number_of_forks(), 0);

	my $maxforks = 50;
	for (1 .. $maxforks) {
		my $pid = fork();
		if($pid == 0) {
			sleep 2;
			exit;
		}
	}
	test("get_number_of_forks()", get_number_of_forks(), $maxforks);
	wait();
	test("get_number_of_forks()", get_number_of_forks(), 0);

	my @needed_software = get_needed_software($0);

	auto_white_balance('tmp/552628351216303/000000.jpg');

	test('is_equal(1, 1)', is_equal(1, 1), 1);
	test('is_equal(1, 0)', is_equal(1, 0), 0);
	test('is_equal({a => 1}, {a => 1})', is_equal({a => 1}, {a => 1}), 1);
	test('is_equal({a => 0}, {a => 1})', is_equal({a => 0}, {a => 1}), 0);

	test('humanreadabletime(14433)', humanreadabletime(14433), '04:00:33');
	test_re('get_random_tmp_folder()', get_random_tmp_folder(), qr#^tmp/\d+#);
	test('is_digit(10)', is_digit(10), 1);
	test('is_digit("a")', is_digit("a"), 0);
	test('isbn_is_valid("asdf")', isbn_is_valid("asdf"), 0);
	test('isbn_is_valid("978-3-16-148410-0")', isbn_is_valid("978-3-16-148410-0"), 1);

	my $final_autocroptest = "./testimages/1.jpg";
	unlink $final_autocroptest if -e $final_autocroptest;
	copy("./testimages/crop.jpg", $final_autocroptest);
	autocrop_image($final_autocroptest);
	my ($width, $height) = imgsize($final_autocroptest);

	test("autocrop_image($final_autocroptest) -> height", $height, 1443);
	test("autocrop_image($final_autocroptest) -> width", $width, 2285);

	my $testisbn = {
		'title' => "Eichmann in Jerusalem. Ein Bericht von der Banalit\x{e4}t des B\x{f6}sen.",
		'publish_date' => 'January 1, 1986',
		'contributors' => '',
		'isbn' => '9783492203081',
		'subtitle' => undef,
		'number_of_pages' => 357
	};
	test('get_info_by_picture("testimages/isbn.jpg")', get_info_by_picture('testimages/isbn.jpg'), $testisbn);
	test('get_info_by_picture("testimages/crop.jpg")', get_info_by_picture('testimages/crop.jpg'), {});
	test('program_installed("ls")', program_installed('ls'), 1);
	test('program_installed("92834ujkefhnswdefhsdw")', program_installed('92834ujkefhnswdefhsdw'), 0);
	test("get_img_average_color('testimages/crop.jpg')", get_img_average_color('testimages/crop.jpg'), "BEACB7");

	test('remove_jpg("test.jpg")', remove_jpg('test.jpg'), 'test');


	if(@failed) {
		warn_error "\n\nFailed tests:\n\n";
		foreach my $failed_test (@failed) {
			warn_error "\t".$failed_test.color("reset")."\n";
		}
		exit @failed;
	} else {
		warn_ok "\n\n".color("underline green")."All tests ran successfully!".color("reset")."\n";
	}
} else {
	initialize_serial($options{serial});

	test_camera();

	main();
}

sub main {
	my $random_tmp_folder = get_random_tmp_folder();
	my $info = {};

	my $has_isbn = 0;
	if(!$options{isbn}) {
		$has_isbn = get_input("Does the book have an ISBN-number?", 1, undef, "has_isbn");
	}

	if($has_isbn) {
		ENTERSCANISBN:
		my $has_barcode = get_input("Does the book have a barcode?", 1, undef, "has_barcode");
		if($has_barcode) {
			notify("ISBN-Scan", "Please press enter to scan the ISBN");
			my $enter = <STDIN>;

			my $file_name = $random_tmp_folder.'/isbn.jpg';
			my $img = take_image($file_name);
			if($img) {
				$info = get_info_by_picture($img);
				if(scalar keys %{$info} == 0) {
					if(get_input("Could not get any ISBN! Try it again?", 1)) {
						goto ENTERSCANISBN;
					}
				}
			} else {
				warn_color "Could not take picture. Enter it manually!";
				goto MANUALISBN;
			}
		} else {
			MANUALISBN:
			my $isbn = get_input("Please enter ISBN manually", 0, 'isbn', "isbn");
			while (!isbn_is_valid($isbn)) {
				$isbn = get_input("Wrong ISBN. Please enter ISBN manually", 0, 'isbn');
			}
			$info = get_info($isbn);
		}
	}

	my $enter = undef;


	my $max_page = 0;
	if($options{max_page}) {
		$max_page = $options{max_page};
	} else {
		$max_page = get_input("Max. page number", 0, 'int', 'max_page');
	}
	my $enable_ocr = 0;
	if(defined $options{ocr}) {
		$enable_ocr = $options{ocr};
	} else {
		$enable_ocr = get_input("Enable OCR?", 1, undef, 'enable_ocr');
	}
	my $sprache = $info->{sprache};
	if($enable_ocr) {
		if(!defined($sprache)) {
			if(defined($options{language})) {
				$sprache = $options{language};
			} else {
				$sprache = get_input("Enter 3-lettered-language code:\n");
			}
		}
	}

	my $enable_page_turner = 0;
	if(defined $options{pageturner}) {
		$enable_page_turner = $options{pageturner};
	} else {
		$enable_page_turner = get_input("Enable automatical page-turner?", 1, undef, "enable_page_turner");
	}

	if(scalar keys %{$info} == 0) {
		if(!$info->{title}) {
			if(defined $options{title}) {
				$info->{title} = $options{title};
			} else {
				$info->{title} = get_input("Book title?", 0, "str", "title");
			}
		}


		if(!$info->{contributors}) {
			if(defined $options{author}) {
				$info->{contributors} = $options{author};
			} else {
				$info->{contributors} = get_input("Author?", 0, "str", "author");
			}
		}
	}

	if($options{titlepage}) {
		notify("Title page", "Press enter for scanning the title page");
		$enter = <STDIN>;
		my $img = take_image("$random_tmp_folder/000000.jpg");
		my $pid = fork();
		die "No fork possible!" if not defined $pid;
		if (not $pid) {
			ocr_file($img);
			exit();
		}
	}
	
	calculcate_width_between_arms();
	release();

	my $turns = ($max_page + ($max_page % 2)) / 2;

	if($turns) {
		notify("Prepare first page", "Please prepare the first page and press enter for automatically scanning the pages");
		$enter = <STDIN>;
		insert();
		$enter = <STDIN>;
		notify("Done preparing", "Please press enter to start scanning");

		toparm_left();

		my @times = ();

		FOREACHSCAN: foreach my $thispage (1 .. $turns) {
			my $starttime = gettimeofday();
			print_status sprintf("$thispage of $turns, %.2f", (($thispage / $turns) * 100))."%";
			if(@times) {
				my $avg_time = mean(@times);
				my $resttime = $avg_time * (($turns - $thispage) + 1);
				
				print_status sprintf("Avg. time: %s, rest time: %s", 
					humanreadabletime($avg_time), 
					humanreadabletime($resttime));
			}
			my $tempfile_right = $thispage.'_right.jpg';
			my $tempfile_left = $thispage.'_left.jpg';

			my $tempfile_right_with_folder = $random_tmp_folder.'/'.$tempfile_right;
			my $tempfile_left_with_folder = $random_tmp_folder.'/'.$tempfile_left;

			$tempfile_right_with_folder = take_image($tempfile_right_with_folder);

			my $img = "$random_tmp_folder/$thispage.jpg";

			if($enable_page_turner) {
				switch_toparm();

				$tempfile_left_with_folder = take_image($tempfile_left_with_folder);

				debug "PID $$";

				my $pid = fork();
				die "No fork possible!" if not defined $pid;
				if (not $pid) {
					while (get_number_of_forks() >= $options{max_forks}) {
						debug "Too many forks (".scalar(get_number_of_forks())."), waiting for a few of them to finish (max: $options{max_forks})";
						sleep 20;
					}
					$img = crop_and_merge($random_tmp_folder, $thispage, $tempfile_left, $tempfile_right);
					ocr_file($img);
					exit();
				} else {
					if($thispage <= $turns) {
						next_page();
					}
				}
			} else {
				if($thispage != $turns) {
					notify("Next page", "Change to next page and press enter (c for cancel)...");
					my $nenter = <STDIN>;
					if($nenter =~ m#c#i) {
						last FOREACHSCAN;
					}
				}
			}

			my $endtime = gettimeofday();
			push @times, $endtime - $starttime;
		}
	}

	release();

	while (wait() != -1) {
		debug "!!! Waiting for forked jobs !!!";
		nanosleep 200_000_000;
	}

	my $pdf_name = $info->{title};
	$pdf_name =~ s#\W#_#g;
	my $pdf_file = $pdf_name.'.pdf';

	my $final_filename = merge_to_pdf($random_tmp_folder, $pdf_file);

	if($final_filename) {
		write_metadata($random_tmp_folder, $pdf_file, $info);

		my $final_file = move_to_final($random_tmp_folder, $pdf_file, $info);
	} else {
		warn_color "Could not create PDF!";
	}

	final_sound();
}

sub final_sound {
	my $command = 'beep -f 130 -l 100 -n -f 262 -l 100 -n -f 330 -l 100 -n -f 392 -l 100 -n -f 523 -l 100 -n -f 660 -l 100 -n -f 784 -l 300 -n -f 660 -l 300 -n -f 146 -l 100 -n -f 262 -l 100 -n -f 311 -l 100 -n -f 415 -l 100 -n -f 523 -l 100 -n -f 622 -l 100 -n -f 831 -l 300 -n -f 622 -l 300 -n -f 155 -l 100 -n -f 294 -l 100 -n -f 349 -l 100 -n -f 466 -l 100 -n -f 588 -l 100 -n -f 699 -l 100 -n -f 933 -l 300 -n -f 933 -l 100 -n -f 933 -l 100 -n -f 933 -l 100 -n -f 1047 -l 400';
	debug_qx($command);
}

sub move_to_final {
	my $tmp = shift;
	my $pdf = shift;
	my $info = shift;

	my $final_folder = 'final/';
	mkdir $final_folder unless -d $final_folder;

	my $author = '';
	if(exists($info->{contributors})) {
		$author = $info->{contributors};
	} else {
		$author = get_input("Author?", 0, "str", "author");
	}

	$author =~ s#\W#_#g;
	my $to_folder = "$final_folder$author";
	mkdir $to_folder unless -d $to_folder;

	if(!-d $final_folder) {
		warn_color "$final_folder not found!";
	}

	my $tmp_file = $tmp;
	if(-d "$tmp_file/out") {
		$tmp_file .= "/out";
	}
	$tmp_file .= "/$pdf";
	my $to_file = "$to_folder/$pdf";

	copy($tmp_file, $to_file) or die "Copy failed: $!";

	return $to_file;
}

sub get_random_tmp_folder {
	my $folder = 'tmp';
	mkdir $folder unless -d $folder;

	my $rand = rand();
	$rand =~ s#^0\.##g;
	my $rand_folder = $folder.'/'.$rand;
	while (-d $rand_folder) {
		$rand = rand();
		$rand =~ s#^0\.##g;
		$rand_folder = $folder.'/'.$rand;
	}

	mkdir $rand_folder or die $!;

	return $rand_folder;
}

sub merge_to_pdf {
	my $dir = shift;
	my $pdfname = shift;
	debug("merge_to_pdf($dir, $pdfname)");

	my $orig_dir = $dir;

	$dir = "$dir/out/";
	if(!-d $dir) {
		debug "$dir does not exist";
		$dir = $orig_dir;
	}

	opendir my $dh, $dir or die "Can't opendir '$dir': $!";
	my @folder = readdir $dh;
	debug "folder: $dir";
	debug_dumper(\@folder);

	my @tiff = grep -f "$dir/$_" && /^\d+\.jpg$/i, @folder;
	if(!@tiff) {
		warn_color "WARNING: No images found!";
	}

	closedir $dh or die "Can't closedir '$dir': $!";

	if(@tiff) {
		my @these_files = ();
		for my $ttiff (sort {
			my $awithoutjpg = remove_jpg($a);
			my $bwithoutjpg = remove_jpg($b);
			if (is_digit($awithoutjpg) && is_digit($bwithoutjpg)) {
			$awithoutjpg <=> $bwithoutjpg
			} else {
			$a cmp $b
			}
			} @tiff) {
			debug "ttiff: $ttiff";
			my $jpegname = $ttiff;
			$jpegname =~ s#\.tiff?#.jpg#g;
			my $jpegpath = "$dir/$jpegname";
			my $this_file_final_pdf = remove_jpg($jpegpath).".pdf";

			if(!$options{ocr}) {
				debug "OCR disabled";
				if(program_installed("convert")) {
					my $converted_code = "convert $jpegpath ".$this_file_final_pdf;
					debug_system($converted_code);
				} else {
					notify("OCR could not be started", "Tesseract not found");
				}
			}
			push @these_files, $this_file_final_pdf;

		}

		if(program_installed("pdfunite")) {
			my $final_name = "$dir/$pdfname";
			my $merge_string = 'pdfunite '.join(' ', @these_files).' '.$final_name;

			debug_system($merge_string);

			return $final_name;
		} else {
			notify("pdfunite not installed!", "pdfunite not installed!");
		}
	} else {
		warn_color "No files found!";
	}
	return undef;
}

sub get_input {
	my $text = shift;
	my $yesno = shift // 0;
	my $type = shift // 'str';
	my $option_var_name = shift // undef;

	notify("The scanner program needs your attention", $text);

	if($yesno) {
		print_normal "$text (y/n):\n";
		my $var = '';
		if($option_var_name && defined($options{$option_var_name})) {
			warn_ok "Getting ".color("reset").color("on_blue black").$option_var_name.
			color("reset").color("green")." from cli-parameter = $options{$option_var_name}";
			$var = $options{$option_var_name};
		}

		while ($var !~ m#^(y|n)$#i) {
			if($var ne '') {
				warn_color "Please answer y or n!";
			}
			$var = <STDIN>;
			$var = '' unless $var;
			chomp $var;
		}

		if($var eq 'y') {
			return 1;
		} else {
			return 0;
		}
	} else {
		print_normal "$text:\n";
		my $var = '';
		if($option_var_name && defined($options{$option_var_name})) {
			warn_ok "Getting ".color("reset").color("on_blue black").$option_var_name.color("reset").color("green")." from cli-parameter = $options{$option_var_name}";
			$var = $options{$option_var_name};
		} else {
			$var = <STDIN>;
		}

		debug $var;
		chomp $var;

		if($type eq 'str') {
			while (!length($var)) {
				$var = <STDIN>;
				chomp $var;
			}
		} elsif ($type eq 'int') {
			while ($var !~ m#^\d+$#) {
				warn_color "Invalid number input `$var`. Try again.";
				$var = <STDIN>;
				chomp $var;
			}
		} elsif ($type eq 'float') {
			while ($var !~ m#^\d+(?:.\d+)?$#) {
				warn_color "Invalid number input `$var`. Try again.";
				$var = <STDIN>;
				chomp $var;
			}
		} elsif ($type eq 'isbn') {
			$var =~ s#-##g;
			while (!isbn_is_valid($var)) {
				warn_color "Invalid isbn input `$var`. Try again.";
				$var = <STDIN>;
				chomp $var;
				$var =~ s#-##g;
			}
		} else {
			die("Unknown type $type");
		}

		return $var;
	}
}

sub prev_page {
	...
}

sub write_metadata {
	my $random_tmp_folder = shift;
	my $file = shift;
	my $folder = $random_tmp_folder;
	if(-d "$folder/out") {
		$folder = "$random_tmp_folder/out";
	}
	my $filename = "$folder/".$file;
	if(!-e $filename) {
		die "$filename not found";
	}
	my $info = shift;
	if(program_installed("exiftool")) {
		my $command = qq#exiftool #;
		if(exists($info->{contributors})) {
			$command .= ' -Author="'.$info->{contributors}.'" ';
		}

		if(exists($info->{title})) {
			$command .= ' -Title="'.$info->{title}.'" ';
		}

		if(exists($info->{isbn})) {
			$command .= ' -Subject="'.$info->{isbn}.'" ';
		}

		if(exists($info->{thumbnail_url})) {
			$command .= ' "-previewimage<=preview/'.$info->{isbn}.'.jpg" ';
		}

		$command .= qq# $filename#;
		debug_qx($command);
	} else {
		warn_color "exiftool is not installed!";
	}
}

sub debug_dumper (@) {
	if($options{debug}) {
		foreach (@_) {
			warn color("on_white blue").(Dumper $_).color("reset")."\n";
		}
	}
}

sub debug (@) {
	if($options{debug}) {
		foreach (@_) {
			warn color("on_white blue").$_.color("reset")."\n";
		}
	}
}

sub get_info_by_picture {
	my $file = shift;
	debug "Trying file $file";
	my $isbn = parse_img_barcode($file);

	if($isbn) {
		debug "ISBN found: $isbn";
		return get_info($isbn);
	} else {
		return +{};
	}
}

sub parse_img_barcode {
	my $img_file = shift;

	if(-e $img_file) {
		debug "File $img_file exists";
		if(program_installed("zbarimg")) {
			my $command = "zbarimg --raw -q $img_file | grep  -E '^97[89]([0-9]{7}|[0-9]{10})\$'";
			my $ret = debug_qx($command);
			chomp $ret;
			my @splitted = split /\R/, $ret;
			$ret = $splitted[0];
			if($ret && isbn_is_valid($ret)) {
				debug "ISBN $ret is valid";
				return $ret;
			} else {
				if($ret) {
					warn_color "ISBN $ret is invalid";
				} else {
					warn_color "No isbn found in $img_file!";
				}
				return undef;
			}
		} else {
			warn_color "zbarimg not installed!";
		}
	} else {
		warn_color "File not found: $img_file";
	}
}

sub get_info {
	my $nr = shift;
	debug "Getting info for $nr";

	if(isbn_is_valid($nr)) {
		debug "$nr is valid";
		my $data = [];

		my $url = "https://openlibrary.org/api/books?bibkeys=ISBN:$nr&format=json&jscmd=details";
		my $site = myget($url);
		$data = parse_json($site);
		$data = $data->{"ISBN:$nr"};

		if(exists($data->{thumbnail_url})) {
			$data->{thumbnail_url} =~ s#-S\.#-L.#g;
			my $preview = './preview/';
			mkdir $preview unless -d $preview;

			my $filename = $preview.$nr.'.jpg';

			if(!-e $filename) {
				my $content = myget($data->{thumbnail_url});
				open my $fh, '>', $filename;
				print $fh $content;
				close $fh;
			}
		}

		my %return_data = ();
		foreach my $type (qw/subtitle number_of_pages title publish_date/) {
			$return_data{$type} = $data->{details}->{$type};
		}

		my @contributors = ();
		foreach my $contributor (@{$data->{details}->{contributors}})  {
			push @contributors, "$contributor->{name} ($contributor->{role})";
		}
		my $contributors_string = join(', ', sort { $a cmp $b } @contributors);

		$return_data{contributors} = $contributors_string;
		$return_data{isbn} = $nr;

		return \%return_data;
	} else {
		warn_color "Wrong isbn $nr";
		return +{};
	}
}

sub myget {
	my $url = shift;

	debug "myget($url)";

	my $md5 = md5_hex($url);

	my $tmp = './myget_cache';
	unless (-d $tmp) {
		mkdir $tmp or die $!;
	}
	my $file = "$tmp/$md5";

	my $site = undef;
	if(-e $file) {
		debug "$file exists";
		open my $fh, "<", $file or die $!;
		while (<$fh>) {
			$site .= $_;
		}
		close $fh;
	} else {
		debug "$file does not exist";
		$site = get($url);
		open my $fh, ">", $file or die $!;
		print $fh $site;
		close $fh;
	}

	return $site;
}

sub isbn_is_valid {
	my $nr = shift;
	debug "isbn_is_valid($nr)";
	if($nr) {
		my $isbn = Business::ISBN->new($nr);
		if($isbn && $isbn->is_valid) {
			debug "$nr is valid";
			return 1;
		} else {
			debug "$nr is invalid";
			return 0;
		}
	} else {
		debug "Empty iban";
		return 0;
	}
}

sub auto_white_balance {
	my $jpegpath = shift;
	if(program_installed("gimp")) {
		if(-e $jpegpath) {
			my $command = qq#gimp -ifd -b '(batch-auto-levels "$jpegpath")' -b '(gimp-quit 0)'#;
			debug_system($command);
		} else {
			warn_color "$jpegpath not found!";
		}
	}
}

sub get_img_average_color {
	my $img = shift;
	if(program_installed("convert")) {
		my $command = qq&convert $img -resize 1x1\\! txt:- | perl -e 'while (<>) { if(/#([A-F0-9]+)/) { print \$1; } }'&;
		my $ret = debug_qx($command);
		debug "Result: $ret";
		return $ret;
	} else {
		warn_color "Imagemagick not installed!";
		return '';
	}
}

sub notify {
	my $title = shift // undef;
	my $message = shift;

	print_status "$message\n";

	if($options{notify}) {
		if(program_installed("notify-send")) {
			my $command = '';
			if($title && $message) {
				$command = qq#notify-send "$title" "$message"#;
			} elsif($title) {
				$command = qq#notify-send "$title" "$title"#;
			} elsif($message) {
				$command = qq#notify-send "$message" "$message"#;
			} else {
				$command = qq#notify-send "$message" "$message"#;
			}
			debug_system($command);
		}
	}
}

sub debug_qx {
	my $command = shift;

	debug $command;
	if(wantarray()) {
		debug "debug_qx in array context";
		my @ret = qx($command);
		debug "$command returned\n======";
		debug_dumper(\@ret);
		debug "\n======";
		return @ret;
	} else {
		debug "debug_qx in scalar context";
		my $ret = qx($command);
		debug "$command returned\n======\n$ret\n======";
		return $ret;
	}
}

sub debug_system {
	my $command = shift;

	debug $command;
	my $ret = system($command);
	debug "$command returned the code $ret";
	return $ret;
}

sub help {

	print_normal <<EOF;
HELP FOR BOOKSCANNER

This program allows using the modified PT80169A-bookscanner, does automatic OCR and a whole lotta' more.

OCR settings:
	--ocr					Enables auto-OCR (enabled)
	--no-ocr				Disables auto-OCR
	--language=deu				Sets the OCR-language (default: deu, other: eng, deu_frak)
	--preprocessing				Enables pre-processing of images before OCR
	--nopreprocessing			Disables pre-processing of images (default)
	--autocropthreshold=VALUE		Sets the threshold for autocropping (default: $options{autocropthreshold})

PDF settings:
	--author="Name"				Sets the author for the file PDF
	--isbn=9783492203081			Set ISBN (e.g. when no barcode is available)
	--has_isbn=yn				y = There is an ISBN, n = there is none
	--title="Title"				Sets the title for the PDF to be produced
	--has_barcode=yn			Sets if there is an ISBN-barcode or not

Hardware settings:
	--serial="/dev/ttyUSB0"			Sets the serial port file for the Arduino (default: $options{serial})
	--pageturner				Enables the automatic page-turner
	--max_page=MAXPAGE			Sets the maximum number of pages to scroll through

Output settings:
	--debug					Enables Debug-Output
	--notify				Enables notifications when subjobs are done

General settings:
	--test					Run tests
	--help					This help menu
	--max_forks=4				Maximum number of OCR-forks (default: $options{max_forks})
	--notitlepage				Disables titlepage

EXAMPLE

perl control.pl --debug --isbn=9783492203081 --max_page=192 --ocr --language=deu --pageturner --title="Title" --author="AUTHOR"
EOF
}

sub analyze_args {
	foreach (@_) {
		if(/^--debug$/) {
			$options{debug} = 1;
		} elsif(/^--notify$/) {
			$options{notify} = 1;
		} elsif(/^--preprocessing$/) {
			$options{preprocessing} = 1;
		} elsif(/^--autocropthreshold=(\d(?:\.\d+))$/) {
			$options{autocropthreshold} = $1;
		} elsif(/^--pageturner$/) {
			$options{pageturner} = 1;
		} elsif(/^--serial=(.*)$/) {
			$options{serial} = $1;
		} elsif(/^--nopreprocessing$/) {
			$options{preprocessing} = 0;
		} elsif(/^--notitlepage$/) {
			$options{titlepage} = 0;
		} elsif(/^--max_page=(\d+)$/) {
			$options{max_page} = $1;
		} elsif(/^--isbn=([0-9-]+)$/) {
			$options{isbn} = $1;
		} elsif(/^--has_isbn=([yn])$/) {
			$options{has_isbn} = $1;
		} elsif(/^--title=(.*)$/) {
			$options{title} = $1;
		} elsif(/^--author=(.*)$/) {
			$options{author} = $1;
		} elsif(/^--ocr$/) {
			$options{ocr} = 1;
		} elsif(/^--no-ocr$/) {
			$options{ocr} = 0;
		} elsif(/^--has_barcode=([yn])$/) {
			$options{has_barcode} = $1;
		} elsif(/^--enable_page_turner=([yn])$/) {
			$options{enable_page_turner} = $1;
		} elsif(/^--test$/) {
			$options{test} = 1;
			$options{notify} = 0;
		} elsif(/^--language=(\w{3})$/) {
			$options{language} = $1;
		} elsif(/^--max_forks=(\d+)$/) {
			$options{max_forks} = $1;
		} elsif(/^--help$/) {
			help();
			exit(0);
		} else {
			help();
			warn_error "Unknown option `$_`\n";
			exit(1);
		}
	}

	if(!$options{test}) {
		if(!-e $options{serial}) {
			$options{serial} = guess_serial_port();
		}
	}

	debug_dumper \%options;
}

sub warn_color (@) {
	my @msg = @_;

	foreach (@msg) {
		warn color("red").$_.color("reset")."\n";
	}
}

sub warn_ok (@) {
	my @msg = @_;

	foreach (@msg) {
		warn color("green").$_.color("reset")."\n";
	}
}

sub program_installed {
	my $program = shift;
	my $ret = qx(whereis $program | sed -e 's/^$program: //');
	chomp $ret;
	my @paths = split(/\s*/, $ret);
	my $exists = 0;
	PATHS: foreach (@paths) {
		if(-e $_) {
			$exists = 1;
			last PATHS;
		}
	}

	if($exists) {
		debug "$program already installed";
	} else {
		warn_color "$program does not seem to be installed. Please install it!";
	}

	return $exists;
}

sub is_digit {
	my $value = shift;
	if($value =~ m#^\d+$#) {
		return 1;
	} else {
		return 0;
	}
}

sub initialize_serial {
	my $serial = shift;
	my $recursive = shift // 0;
	if(-e $serial) {
		debug("initialize_serial($serial)");
		$ob = Device::SerialPort->new($serial) or die $!;
		$ob->baudrate(38400);
		$ob->parity("none");
		$ob->stopbits(1);
		$ob->write_settings;
		#print_to_serial_port("", "done", $recursive);
	} else {
		die "ERROR! $serial could not be found!";
	}
}

sub release {
	debug("release");

	print_to_serial_port("release", "done");
}

sub insert {
	debug("insert");

	print_to_serial_port("insert", "done insert");
}

sub toparm_left {
	debug("toparm_left");

	print_to_serial_port("toparm left", "done toparm left");
}

sub next_page {
	debug("next_page");

	print_to_serial_port("p", "done");
}

sub switch_toparm {
	debug("switch_toparm");

	print_to_serial_port("switch toparm", "done switch");
}

sub crop_and_merge {
	my $tmp = shift;
	my $pagenr = shift;
	my $img1 = shift;
	my $img2 = shift;
	debug("crop(tmp = $tmp, pagenr = $pagenr, img1 = $img1, img2 = $img2)");

	my $left = crop_single_file($tmp, $img1, 0);
	my $right = crop_single_file($tmp, $img2, 1);

	return merge($tmp, $left, $right, $pagenr);
}

sub merge {
	my $tmp = shift;
	my $left = shift;
	my $right = shift;
	my $out = shift;
	debug("merge(tmp = $tmp, left = $left, right = $right, out = $out)");
	$out .= '.jpg';
	my $system = "convert +append $left $right $tmp/$out";
	debug_qx($system);

	return "$tmp/$out";
}

sub crop_single_file {
	my $tmp = shift;
	my $img = shift;
	my $nr = shift;

	debug("crop_single_file(tmp = $tmp, img = $img, nr = $nr)");

	my $output = $img;
	$output =~ s#\.jpg$##g;
	$output .= "_%d.jpg";
	my $system = "convert -crop 50%x100% +repage $tmp/$img $tmp/$output";
	debug_qx($system);

	return sprintf("./$tmp/$output", $nr);
}

sub mean {
	my $ret = 0;
	eval {
		$ret = sum(@_) / @_;
	};

	if($@) {
		cluck("Error: $@");
	}
	return $ret;
}


sub humanreadabletime {
	my $hourz = int($_[0] / 3600);
	my $leftover = $_[0] % 3600;
	my $minz = int($leftover / 60);
	my $secz = int($leftover % 60);

	return sprintf ("%02d:%02d:%02d", $hourz,$minz,$secz)
}

sub remove_jpg {
	my $filename = shift;
	$filename =~ s#\.jpe?g$##g;
	return $filename;
}

sub autocrop_image {
	my $path = shift;

	die "ERROR: $path does not exist!" unless -e $path;

	debug("autocrop_image(path = $path)");

	my $image = Image::Magick->new;
	$image->Read($path);
	my ($width, $height) = imgsize($path);

	my $n = 20;

	my $avg_first_n_lines_top = 0;
	my $offset_y = 0;

	debug("TOPDOWNSCANNER");
	TOPDOWNSCANNER: foreach my $line (0 .. $height) {
		my @pixels = ();
		foreach my $col (0 .. $width) {
			if($col % 100 == 0) {
				push @pixels, mean($image->GetPixel(x => $col, y => $line));
			}
		}
		
		my $mean = mean(@pixels);
		if($line < ($n + 1)) {
			$avg_first_n_lines_top += $mean;
		} elsif($line == ($n + 1)) {
			$avg_first_n_lines_top = $avg_first_n_lines_top / $n;
		} else {
			my $diffpercent = ($mean / $avg_first_n_lines_top);
			if($diffpercent >= $options{autocropthreshold}) {
				$offset_y = $line;
				last TOPDOWNSCANNER;
			}
		}
	}
	debug("TOP: $offset_y");

	my $avg_first_n_lines_bottom = 0;
	my $imgstartedbottom = 0;

	debug("DOWNTOPSCANNER");
	DOWNTOPSCANNER: foreach my $line (reverse(0 .. $height)) {
		my @pixels = ();
		foreach my $col (0 .. $width) {
			if($col % 100 == 0) {
				push @pixels, mean($image->GetPixel(x => $col, y => $line));
			}
		}

		my $mean = mean(@pixels);

		my $diffpercent = ($mean / $avg_first_n_lines_top);

		if($diffpercent >= $options{autocropthreshold}) {
			$imgstartedbottom = $line;
			last DOWNTOPSCANNER;
		}
	}
	debug("BOTTOM: $imgstartedbottom");

	my $offset_x = 0;

	debug("LEFTRIGHTSCANNER");
	LEFTRIGHTSCANNER: foreach my $col (0 .. $width) {
		my @pixels = ();
		foreach my $line (0 .. $height) {
			if($line % 10 == 0) {
				push @pixels, mean($image->GetPixel(x => $col, y => $line));
			}
		}

		my $mean = mean(@pixels);

		my $diffpercent = ($mean / $avg_first_n_lines_top);

		if($diffpercent >= $options{autocropthreshold}) {
			$offset_x = $col;
			last LEFTRIGHTSCANNER;
		}
	}
	debug("offset_x: $offset_x");

	my $imgstartedright = 0;

	debug("RIGHTLEFTSCANNER");
	RIGHTLEFTSCANNER: foreach my $col (reverse(0 .. $width)) {
		my @pixels = ();
		foreach my $line (0 .. $height) {
			if($line % 10 == 0) {
				push @pixels, mean($image->GetPixel(x => $col, y => $line));
			}
		}

		my $mean = mean(@pixels);

		my $diffpercent = ($mean / $avg_first_n_lines_top);

		if($diffpercent >= $options{autocropthreshold}) {
			$imgstartedright = $col;
			last RIGHTLEFTSCANNER;
		}
	}
	debug("RIGHT: $imgstartedright");

	copy($path, "$path.copy");

	my $new_width = $width - $offset_x - ($width - $imgstartedright);
	my $new_height = $imgstartedbottom - $offset_y;

	debug("old_height: $height, new_height: $new_height");
	debug("old_width: $width, new_width: $new_width");

	$image->Crop(geometry => $new_width."x".$new_height."+".$offset_x."+".$offset_y."!");
	$image = $image->Write($path);
	return $path;
}

sub test_camera {
	my $testimage = "tmp/test.jpg";
	unlink($testimage) if -e $testimage;
	take_image($testimage, 0);
	if(-e $testimage) {
		return 1;
	} else {
		return 0;
	}
}

sub take_image {
	my $filename = shift;

	if(program_installed("gphoto2")) {
		while (!-e $filename) {
			my $string = qq(gphoto2 --no-keep --force-overwrite -F 1 --capture-image-and-download --filename="$filename");
			debug_system($string);
			if(!-e $filename) {
				notify("KAMERAFEHLER!", "KAMERAFEHLER!");
				get_input("Try Again!", 1);
			} else {
				no_rotation($filename);
			}
		}
		return $filename;
	} else {
		return undef;
	}
}

sub is_equal {
	my $d1 = shift;
	my $d2 = shift;

	if(Compare($d1, $d2)) {
		return 1;
	} else {
		return 0;
	}
}

sub test {
	my $testname = shift;
	my $actual_result = shift;
	my $shouldbe = shift;

	my $delimiter = "=" x 30;

	print_normal "$delimiter\n$testname: ";
	if(Compare($actual_result, $shouldbe)) {
		print_ok "OK";
	} else {
		push @failed, $testname;
		warn_error "ERROR! Is: \n".Dumper($actual_result)."\nShould be:\n".Dumper($shouldbe);
	}
}

sub test_re {
	my $testname = shift;
	my $actual_result = shift;
	my $shouldbe = shift;

	my $delimiter = "=" x 30;

	print_status "$delimiter\n$testname: ";
	if($actual_result =~ $shouldbe) {
		print_ok "OK";
	} else {
		if($testname !~ /TESTTHISTEST/) {
			push @failed, $testname;
			warn_error "ERROR! Is: \n".Dumper($actual_result)."\nShould be:\n".Dumper($shouldbe);
		}
	}
}


sub needs_rotation {
	my $path = shift;
	debug("needs_rotation($path)");

	if(-e $path) {
		my ($width, $height) = imgsize($path);
		debug("\t$path: $width $height");
		if($height < $width) {
			return 1;
		} else {
			return 0;
		}
	} else {
		print color("red")."$path not found!!!!".color("reset");
		return undef;
	}
}

sub print_normal (@) {
	foreach my $this_text (@_) {
		print "$this_text\n";
	}
}

sub print_ok (@) {
	foreach my $this_status (@_) {
		my $this_text = color("underline green").$this_status.color("reset")."\n";
		print $this_text;
	}
}

sub print_status (@) {
	foreach my $this_status (@_) {
		my $this_text = color("on_blue green").$this_status.color("reset")."\n";
		print $this_text;
	}
}

sub warn_error (@) {
	foreach my $this_status (@_) {
		my $this_text = color("red").$this_status.color("reset")."\n";
		warn $this_text;
	}
}

sub no_rotation {
	my $filename = shift;

	if(program_installed("exiftool")) {
		my $string = qq#exiftool -n -Orientation=0 $filename#;
		return debug_system($string);
	} else {
		warn_error "exiftool not installed!";
	}
}

sub deskew_image {
	my $image = shift;

	my $deskew_command = "mv $image $image.before_deskew.jpg; ./deskew $image.before_deskew.jpg -o $image";
	debug_qx($deskew_command);
}

sub ocr_file {
	my $jpegpath = shift;
	if($options{ocr}) {
		if($options{preprocessing}) {
			auto_white_balance($jpegpath);
			autocrop_image($jpegpath);
			deskew_image($jpegpath);
		}
		debug "OCR enabled";

		if(program_installed('convert')) {
			my $border_command = qq#convert $jpegpath -bordercolor White -border 10x10 $jpegpath#;
			debug_system($border_command);
		}

		if(program_installed('tesseract')) {

			my $ocr_command = "tesseract -l $options{language} $jpegpath ".remove_jpg($jpegpath).' pdf';
			debug_system($ocr_command);
		} else {
			notify("OCR could not be started", "Tesseract not found");
		}
	}
}

sub get_number_of_forks {
	my $number_of_forks = 0;
	for my $p (@{new Proc::ProcessTable->table}){
		$number_of_forks++ if($p->ppid == $$);
	}
	return $number_of_forks;

=head
	if(program_installed("pgrep")) {
		my @forks = split(/\n/, debug_qx('pgrep -P '.$mainpid));
		return @forks;
	} else {
		die "ERROR!!!! pgrep not installed!";
	}
=cut
}

sub guess_serial_port {
	my $default = '/dev/ttyUSB';
	for (0 .. 99) {
		my $this = $default.$_;
		if(-e $this) {
			return $this;
		}
	}
	
	warn "NO SERIAL PORT FOUND!!!";
}

sub print_to_serial_port {
	my $string = shift;
	my $waitfor = shift;
	my $recursive = shift // 0;
	debug("print_to_serial_port($string, $waitfor, $recursive)");

	if(!$options{serial} || !-e $options{serial}) {
		$options{serial} = guess_serial_port();
		if($recursive >= 4) {
			die "Recursion error!";
		} else {
			$recursive++;
			initialize_serial($options{serial}, $recursive);
		}
	}
	
	if($string ne "") {
		debug("Printing `$string` to $options{serial}");
		$ob->write("$string\n");
		debug("Done printing `$string` to $options{serial}, waiting for output");
	} else {
		debug "Not printing empty string to $options{serial}";
	}

	$ob->are_match("\n"); 
	my $gotit = "";
	my $i = 0;
	while ($gotit !~ /$waitfor/) {
		die "$options{serial} not found!" unless -e $options{serial};
		$gotit = $ob->lookfor;
		chomp $gotit;
		$gotit =~ s#\r##g;
		debug "$i: Printed `$string`; waiting for `$waitfor`; got Serial-String: >$gotit<";
		die "Aborted without match\n" unless (defined $gotit);
		nanosleep 100_000_000;
		$i++;
	}

	$ob->lookclear;
}

sub get_needed_software {
	my $script = shift;
	debug "get_needed_software($script)";

	my @needed = ();
	open my $fh, '<', $script;
	while (my $line = <$fh>) {
		if($line !~ /^\s*test/ && $line =~ /program_installed\(("|')([^"']*)\1\)/) {
			my $this_program = $2;
			if(!grep( $this_program eq $_ , @needed)) {
				push @needed, $this_program;
			}
		}
	}
	close $fh;
	@needed = sort { $a cmp $b } @needed;
	return @needed;
}

sub install_needed_software {
	debug "install_needed_software()";
	my @needed = get_needed_software($0);

	my $os_is_debian_or_ubuntu = debug_qx(qq#lsb_release -a 2>/dev/null | egrep -i "ubuntu|debian" | wc -l#);
	chomp $os_is_debian_or_ubuntu;

	if(!$os_is_debian_or_ubuntu) {
		die "Auto-installation only works with Debian or Ubuntu!";
	}

	my %programs = (
		'convert' => [
			'apt-get -y install imagemagick'
		],
		'exiftool' => [
			'apt-get -y install libimage-exiftool-perl perl-doc'
		],
		'gimp' => [
			'apt-get -y install gimp'
		],
		'gphoto2' => [
			'apt-get -y install gphoto2'
		],
		'notify-send' => [
			'apt-get -y install libnotify-bin'
		],
		'pdfunite' => [
			'apt-get -y install poppler-utils'
		],
		'pgrep' => [
			'apt-get -y install procps'
		],
		'tesseract' => [
			'apt-get -y install g++ autoconf automake libtool pkg-config libpng-dev libtiff5-dev zlib1g-dev'.
			'automake ca-certificates g++ git libtool libleptonica-dev make pkg-config asciidoc libpango1.0-dev',
			'mkdir ~/tesseractsource',
			'cd ~/tesseractsource; git clone --depth 1 https://github.com/tesseract-ocr/tesseract.git',
			'cd ~/tesseractsource/tesseract; ./autogen.sh; autoreconf -i; ./configure; make; make install; ldconfig'

		],
		'zbarimg' => [
			'apt-get -y install zbar-tools python-qrtools libbarcode-zbar-perl'
		]
	);

	foreach my $this_program (@needed) {
		if(program_installed($this_program)) {
			debug "$this_program is installed!";
		} else {
			if(exists($programs{$this_program})) {
				my $login = (getpwuid $>);
				die "Must run as root" if $login ne 'root';
				debug "Installing $this_program...\n";
				my @commands = @{$programs{$this_program}};

				foreach my $this_command (@commands) {
					if(debug_system($this_command)) {
						die "ERROR installing $this_command";
					} else {
						debug "OK, installed $this_command";
					}
				}
			} else {
				die("NO RULES FOR INSTALLING $this_program!!!");
			}
		}
	}
}

sub calculcate_width_between_arms {
	my $x = get_input("Height of Toparm?", 0, "float", "heighttoparm");

	my $width_between_arms = (2.25 * $x) + 14.875;
	$width_between_arms = int($width_between_arms + 0.5);

	my $arm_from_center = $width_between_arms / 2;
	$arm_from_center = int($arm_from_center + 0.5);

	print "Width between arms: $width_between_arms, width between each arm and center: $arm_from_center\n";

	my $enter = <STDIN>;
}
