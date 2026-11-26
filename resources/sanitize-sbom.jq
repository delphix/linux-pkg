# Sanitise a Syft-generated CycloneDX SBOM for external consumption.
#
# Applied by sanitize_sbom() in lib/common.sh to each <deb>.deb.cdx.json before
# it is validated and uploaded, unless CYCLONEDX_FILTERING is set to "false".
#
# Raw Syft output is not suitable to publish as-is: on delphix-virtualization it
# is 4.7 MB, of which roughly three quarters is repetition, and it records the
# absolute path of every component inside the package.
#
#   1. Replace the `dependencies` graph, and type the root component.
#
#      Syft emits relationships it can observe, which for a directory scan means
#      jar containment ("this WAR bundles these jars"), not resolved dependency
#      edges. It covers about 30% of components, with no `compositions` element
#      declaring it incomplete, so a consumer would reasonably misread a missing
#      entry as "this component has no dependencies". It also holds dangling
#      bom-refs pointing at the per-file components that
#      SYFT_FILE_METADATA_SELECTION=none suppresses, and de-duplication below
#      would orphan many more. It is dropped and rebuilt at the end of this
#      filter as a flat graph declared `incomplete`, alongside setting the root
#      component's type to "application" -- see the comments there.
#
#   2. Drop every property except syft:cpe23 and syft:package:type.
#
#      This removes the internal path leak (syft:location:*:path and
#      syft:metadata:virtualPath, which together expose several hundred
#      directories under /opt/delphix) and metadata that merely restates the
#      purl (syft:metadata:-:groupID / :artifactID).
#
#      syft:cpe23 is retained because the CycloneDX schema allows a single
#      top-level `cpe`, while Syft derives several candidate CPEs per component
#      to improve the odds of matching NVD, whose dictionary has no canonical
#      naming convention. Those candidates are the fallback matching path for
#      components whose primary CPE guess is wrong. Note this is for Mend's
#      benefit rather than Grype's: Grype disables CPE matching for Java by
#      default (match.java.using-cpes), so for the great majority of components
#      here it matches on the purl instead.
#
#      syft:package:type is retained because it is the only record of a
#      component's ecosystem for anything whose purl does not carry one --
#      pkg:generic components and the PE binaries Syft finds without assigning
#      a purl at all. Without it those are reported as "UnknownPackage" rather
#      than "binary". Components with a pkg:maven purl are unaffected, as the
#      type is derived from the purl itself.
#
#   3. Merge-dedupe components.
#
#      Keyed on purl, falling back to name+version+type: a purl-only key would
#      silently drop the Windows binaries found by Syft's PE cataloger, which
#      carry a cpe but no purl, and a name+version key would wrongly merge
#      distinct components that share a name at version "UNKNOWN".
#
#      Duplicates are merged rather than reduced to the first occurrence, since
#      Syft does not detect the same metadata at every location -- keeping only
#      the first silently loses licences and hashes that a later copy carried.
#      A duplicate's differing primary CPE is demoted into syft:cpe23 so that no
#      matching coordinate is lost to the merge.
#
#   4. Give each Java archive its SHA-1 in `hashes`.
#
#      Syft computes the SHA-1 of every jar, nested ones included, but its
#      CycloneDX encoder records it only in a URL-less "build-meta"
#      externalReference. Mend reads `hashes`, and falls back to matching a
#      Maven component by its SHA-1 when the coordinates Syft guessed from the
#      jar's manifest are wrong. The hash is copied into `hashes`, where every
#      scanner looks for it.
#
#   5. Describe the third-party programs Syft's binary cataloger finds.
#
#      Syft types these "application", and Mend's importer skips that type
#      altogether. They are retyped "library". OpenSSL and 7-Zip are also given
#      a pkg:conan purl, the only form Mend identifies them by; Mend ignores
#      the CPE whenever a purl is present, and supports neither pkg:generic nor
#      pkg:github. Syft names OpenSSL and stunnel after their version banners,
#      which yields CPEs no database knows, so those are replaced. Mend cannot
#      identify stunnel, Node.js, bash, jq or rust in any form, but listing them
#      as libraries with correct CPEs keeps the SBOM complete for every other
#      consumer. Delphix's own programs, and those whose origin is not known
#      here, are left as Syft found them.

def allhashes:
  (.hashes // [])
  + [ (.externalReferences // [])[] | select(.type == "build-meta") | .hashes[]? ];

def cpe($vendor; $product):
  "cpe:2.3:a:\($vendor):\($product):\(.version):*:*:*:*:*:*:*";

# Replace a component's identity, dropping Syft's candidate CPEs, which were
# all derived from the wrong name.
def reidentify($name; $cpe; $purl):
  .type = "library"
  | .name = $name
  | .cpe = $cpe
  | if $purl == null then del(.purl) else .purl = $purl end
  | .properties = [ (.properties // [])[] | select(.name != "syft:cpe23") ]
  | if (.properties | length) == 0 then del(.properties) else . end;

def bundled_binary:
  if .type != "application" or .version == null or .version == "UNKNOWN" then .
  elif .name == "7-Zip" then
    reidentify("7-Zip"; cpe("7-zip"; "7-zip"); "pkg:conan/7zip@\(.version)")
  elif .name == "The OpenSSL Toolkit" then
    reidentify("OpenSSL"; cpe("openssl"; "openssl"); "pkg:conan/openssl@\(.version)")
  elif (.name | startswith("stunnel ")) then
    reidentify("stunnel"; cpe("stunnel"; "stunnel"); null)
  elif (.purl // "" | test("^pkg:generic/(bash|jq|node|rust)@")) then
    .type = "library"
  else . end;

def keepprops:
  [ (.properties // [])[]
    | select(.name | test("^syft:(cpe23|package:type)$")) ];

# Syft omits `components` altogether -- rather than emitting an empty array --
# when it finds nothing in the scanned payload, which happens for a package
# whose .deb holds only content no cataloger recognises. Normalise that to an
# empty array first, or every iteration below fails with "Cannot iterate over
# null" and takes the build with it.
.components //= []
| del(.dependencies)
| .components |= (
    group_by(.purl // ([.name, .version, .type] | tostring))
    | map(
        reduce .[] as $c ({};
          if (. | length) == 0 then
            ($c | .properties = keepprops | .hashes = (allhashes | unique))
          else
              .licenses           = (((.licenses           // []) + ($c.licenses           // [])) | unique)
            | .externalReferences = (((.externalReferences // []) + ($c.externalReferences // [])) | unique)
            | .hashes             = (((.hashes             // []) + ($c | allhashes))           | unique)
            | .properties         = (
                ( (.properties // [])
                  + ($c | keepprops)
                  + ( if ($c.cpe != null and $c.cpe != .cpe)
                      then [ { "name": "syft:cpe23", "value": $c.cpe } ]
                      else [] end )
                ) | unique
              )
          end
        )
        # A candidate identical to the component's own primary `cpe` adds
        # nothing -- that value is already carried in the standard field.
        | (.cpe // "") as $primary
        | .properties = [ (.properties // [])[]
                          | select(.name != "syft:cpe23" or .value != $primary) ]
        | if (.licenses           | length) == 0 then del(.licenses)           else . end
        | if (.externalReferences | length) == 0 then del(.externalReferences) else . end
        | if (.hashes             | length) == 0 then del(.hashes)             else . end
        | if (.properties         | length) == 0 then del(.properties)         else . end
      )
    | map(bundled_binary)
  )

# Mend's CycloneDX importer only treats metadata.component as the project root
# when it is application-typed; Syft emits "file" because generate_sbom() scans
# an extracted directory. Without this the root is not recognised at all.
| .metadata.component.type = "application"

# Re-state the dependency graph rather than leaving it absent.
#
# Syft's own graph was dropped above: it covered ~30% of components, encoded jar
# containment rather than resolved dependencies, and held dangling bom-refs. But
# leaving `dependencies` out entirely means each consumer falls back to its own
# default -- Mend, for one, treats a component with no declared relationship as a
# direct dependency of the root. Declaring that explicitly says the same thing
# unambiguously, and connects the root component, which Syft leaves unreferenced
# even in its own output.
#
# `compositions: incomplete` is what keeps this honest: it states that the
# relationships here are not a resolved dependency graph, so a flat tree is not
# mistaken for the real hierarchy. Recovering that would require scanning the
# build rather than the packaged .deb -- see CP-13467.
| .metadata.component["bom-ref"] as $root
| .dependencies = [
    { "ref": $root, "dependsOn": [ .components[]["bom-ref"] ] }
  ]
| .compositions = [
    { "aggregate": "incomplete", "dependencies": [ $root ] }
  ]
