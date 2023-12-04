#!/bin/bash

mkdir ./release

#################################################

# Download Github assets requirement:
dl_gh() {
	for repo in $1 ; do
	wget -qO- "https://api.github.com/repos/$2/$repo/releases/$3" \
	| jq -r '.assets[] | "\(.browser_download_url) \(.name)"' \
	| while read -r url names; do
		echo "Downloading $names from $url"
		wget -q -O "$names" $url
	done
	done
echo "All assets downloaded"
}

#################################################

# Get patches list:
get_patches_key() {
	excludePatches=""
	includePatches=""
	while IFS= read -r line1; do
		excludePatches+=" -e \"$line1\""
	done < src/patches/$1/exclude-patches
	export excludePatches
	while IFS= read -r line2; do
		includePatches+=" -i \"$line2\""
	done < src/patches/$1/include-patches
	export includePatches
}

#################################################

# Find version supported:
get_ver() {
	version=$(jq -r --arg patch_name "$1" --arg pkg_name "$2" '
	.[]
	| select(.name == $patch_name)
	| .compatiblePackages[]
	| select(.name == $pkg_name)
	| .versions[-1]
	' patches.json)
}

#################################################

# Download apks files from APKMirror:
_req() {
	if [ "$2" = - ]; then
		wget -nv -O "$2" --header="$3" "$1"
	else
		local dlp
		dlp="$(dirname "$2")/$(basename "$2")"
		if [ -f "$dlp" ]; then
			while [ -f "$dlp" ]; do sleep 1; done
			return
		fi
		wget -nv -O "$dlp" --header="$3" "$1" || return 1
	fi
}
req() {
	user_agents=("User-Agent: Mozilla/5.0 (X11; Linux x86_64; rv:107.0) Gecko/20100101 Firefox/107.0" "User-Agent: Mozilla/5.0 (X11; Linux x86_64; rv:106.0) Gecko/20100101 Firefox/114.0" "User-Agent: Mozilla/5.0 (X11; Linux x86_64; rv:106.0) Gecko/20100101 Firefox/112.0" "User-Agent: Mozilla/5.0 (X11; Linux x86_64; rv:106.0) Gecko/20100101 Firefox/116.0" "User-Agent: Mozilla/5.0 (X11; Linux x86_64; rv:108.0) Gecko/20100101 Firefox/108.0")
	random_user_agent=$(shuf -n 1 -e "${user_agents[@]}")
	_req "$1" "$2" "$random_user_agent"
}

dl_apk() {
	local url=$1 regexp=$2 output=$3
	url="https://www.apkmirror.com$(req "$url" - | tr '\n' ' ' | sed -n "s/href=\"/@/g; s;.*${regexp}.*;\1;p")"
	sleep 5
	echo "$url"
	url="https://www.apkmirror.com$(req "$url" - | grep "downloadButton" | sed -n 's;.*href="\(.*key=[^"]*\)">.*;\1;p')"
	sleep 5
   	url="https://www.apkmirror.com$(req "$url" - | grep "please click" | sed -n 's#.*href="\(.*key=[^"]*\)">.*#\1#;s#amp;##p')&forcebaseapk=true"
	sleep 5
    echo "$url"
	req "$url" "$output"
}

get_apk() {
	if [[ -z $4 ]]; then
		url_regexp='APK</span>[^@]*@\([^#]*\)'
	else
		local os dpi
		[[ -f $5 ]] && dpi="[^@]*$5"
		[[ -f $6 ]] && os="[^@]*$6"
		case $4 in
			arm64-v8a) url_regexp='arm64-v8a'"$os"''"$dpi"'</div>[^@]*@\([^"]*\)' ;;
			armeabi-v7a) url_regexp='armeabi-v7a'"$os"''"$dpi"'</div>[^@]*@\([^"]*\)' ;;
			x86) url_regexp='x86'"$os"''"$dpi"'</div>[^@]*@\([^"]*\)' ;;
			x86_64) url_regexp='x86_64'"$os"''"$dpi"'</div>[^@]*@\([^"]*\)' ;;
			*) return 1 ;;
		esac 
	fi
	export version="$version"
	if [[ -z $version ]]; then
 		local list_ver
  		list_ver=$(req "https://www.apkmirror.com/uploads/?appcategory=$2" -)
    		version=$(sed -n 's;.*<a class="fontBlack" href="/apk/'"$3"'-.*-release/">[^0-9]*\(.*\)</a> </h5>.*;\1;p' <<<"$list_ver" | grep -v 'beta\|alpha' | sed 's/\([0-9\.]*\).*/\1/' | head -n 1)
	fi
	echo "Downloading $2 $4 version: $version $5 $6"
	local base_apk="$1.apk"
	local dl_url=$(dl_apk "https://www.apkmirror.com/apk/$3-${version//./-}-release/" \
						  "$url_regexp" \
						  "$base_apk")
}

#################################################

# Patching apps with Revanced CLI:
patch() {
	if [ -f "$1.apk" ]; then
		local p b m ks a
		if [ "$3" = inotia ]; then
			p="patch " b="--patch-bundle" m="--merge" a="" ks="_ks"
			echo "Patching with Revanced-cli inotia"
		else
			if [[ $(ls revanced-cli-*.jar) =~ revanced-cli-([0-9]+) ]]; then
				num=${BASH_REMATCH[1]}
				if [ $num -ge 4 ]; then
					p="patch " b="--patch-bundle" m="--merge" a="" ks="ks"
					echo "Patching with Revanced-cli version 4+"
				elif [ $num -eq 3 ]; then
					p="patch " b="--patch-bundle" m="--merge" a="" ks="_ks"
					echo "Patching with Revanced-cli version 3"
				elif [ $num -eq 2 ]; then
					p="" b="-b" m="-m" a="-a " ks="_ks"
					echo "Patching with Revanced-cli version 2"
				else
					echo "No revanced-cli supported"
					exit 1
				fi
			else
				echo "No revanced-cli supported"
				exit 1
			fi
		fi
		eval java -jar revanced-cli*.jar $p\
		$b revanced-patches*.jar \
		$m revanced-integrations*.apk\
		$excludePatches\
		$includePatches \
		--options=./src/options/$2.json \
		--out=./release/$1-$2.apk \
		--keystore=./src/$ks.keystore \
		$a$1.apk
		unset version
		unset excludePatches
		unset includePatches
	else 
		exit 1
	fi
}

#################################################

# Split architectures using Revanced CLI, created by j-hc:
archs=("arm64-v8a" "armeabi-v7a" "x86_64" "x86")
libs=("x86_64 x86 armeabi-v7a" "x86_64 x86 arm64-v8a" "x86 armeabi-v7a arm64-v8a" "x86_64 armeabi-v7a arm64-v8a")
gen_rip_libs() {
	for lib in $@; do
		echo -n "--rip-lib $lib "
	done
}
split_arch() {
	if [ -f "./release/$1.apk" ]; then
		java -jar revanced-cli*.jar patch \
		--patch-bundle revanced-patches*.jar \
		$3 \
		--keystore=./src/ks.keystore \
		--out=./release/$2.apk\
		./release/$1.apk
	else 
		exit 1
	fi
}

#################################################
