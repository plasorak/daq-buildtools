#!/bin/bash

source ${DBT_ROOT}/scripts/dbt-setup-tools.sh
if [[ "$?" != 0 ]]; then
    echo "The source of dbt-setup-tools.sh failed; this may mean you need to set up the dbt-buildtools environment. Exiting..." >&2
    exit 1
fi

view_only_option="--view-differences-only"

if [[ "$#" != "1" && "$#" != "2" ]]; then

cat<<EOF >&2

Usage: $(basename $0) <file or directory to examine> ( $view_only_option )

Given a file, this script will apply clang-format to that file

Given a directory, it will apply clang-format to all the
source (*.cxx, *.cpp) and header (*.hpp) files in that directory as well as all
of its subdirectories.

If the optional $view_only_option argument is supplied, then
instead of actually editing the files, it'll simply show what edits
would be made

EOF

    exit 1
fi

filename=$1
arg2=$2

if [[ ! -e $filename ]]; then
    error "Unable to find $filename; exiting..." 
fi

differences_only=false
if [[ -n $arg2 ]]; then
    if [[ "$arg2" == "--view-differences-only" ]]; then
	differences_only=true
    else
	error "Only allowed second argument is \"--view-differences-only\""
    fi
fi

if [[ -z ${DBT_WORKAREA_ENV_SCRIPT_SOURCED:-} ]]; then
 
error "
It appears you haven't yet executed "dbt-workarea-env"; please do so before running this 
script. Exiting..."

fi

which clang-format > /dev/null 2>&1
retval=$?

if [[ "$retval" != "0" ]]; then
    clang_version=$( ups list -aK+ clang | sort -n | tail -1 | sed -r 's/^\s*\S+\s+"([^"]+)".*/\1/' )
    
    if [[ -n $clang_version ]]; then

	# JCF, May-21-2021

	# Surely this explicit setup of ups products directories can
	# be avoided if this script is called after a work area
	# environment's already been set up...

	for proddir in $( echo $PRODUCTS | tr ":" " " ) ; do
	    . $proddir/setup
	done

	setup clang $clang_version
	retval="$?"

	if [[ "$retval" == "0" ]]; then
	    echo "Set up clang $clang_version"
	else
	    error "
Error: there was a problem executing \"setup clang $clang_version\"
(return value was $retval). Please check the products directories
you've got set up. Exiting..."
	fi
    fi
fi


clang_format_link="https://raw.githubusercontent.com/DUNE-DAQ/daq-buildtools/develop/configs/.clang-format"

mv -f .clang-format .clang-format.previous  2>/dev/null # In case .clang-format's been updated in daq-buildtools since this script was run

curl -O $clang_format_link
if [[ "$?" != "0" ]]; then
    error "
There was a problem running 

curl -O $clang_format_link

Exiting..."

fi

# Now with the latest .clang-format file, let's figure out what to format

files_to_format=""
extensions="*.hpp *.cpp *.cxx *.hxx"

if [[ -d $filename ]]; then
    files_to_format=$( for extension in $extensions ; do find . -name $extension; done )
elif [[ -f $filename ]]; then
    extension=$( echo $filename | sed -r 's/.*\.([^.]+)$/\1/' )

    if [[ "$extensions" =~ .*\*\.$extension ]]; then 
	files_to_format=$filename
    else
	error "Filename provided has unknown extension; exiting..." 
    fi
fi

for orig_file in $files_to_format ; do

    echo "Processing ${orig_file}..."
    tmpfile=/tmp/$( uuidgen )
    clang-format -style=file $orig_file > $tmpfile
    diff $tmpfile $orig_file
    diff_retval="$?"

    if [[ "$diff_retval" == 0 ]]; then
	echo
	echo "$orig_file already properly formatted"
	echo
    elif ! $differences_only ; then
	echo "Updating $orig_file with new formatting"
	mv $tmpfile $orig_file
    fi

done

exit 0
