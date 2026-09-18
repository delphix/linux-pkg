# Sanitise a Syft-generated CycloneDX sidecar for external consumption.
#
# Applied by sanitize_sbom() in lib/common.sh to each <deb>.deb.cdx.json before
# it is validated and uploaded, unless CYCLONEDX_FILTERING is set to "false".
#
# Raw Syft output is not suitable to publish as-is: on delphix-virtualization it
# is 4.7 MB, of which roughly three quarters is repetition, and it records the
# absolute path of every component inside the package.
#
#   1. Drop the `dependencies` graph.
#
#      Syft emits relationships it can observe, which for a directory scan means
#      jar containment ("this WAR bundles these jars"), not resolved dependency
#      edges. It covers about 30% of components, with no `compositions` element
#      declaring it incomplete, so a consumer would reasonably misread a missing
#      entry as "this component has no dependencies". It also holds dangling
#      bom-refs pointing at the per-file components that
#      SYFT_FILE_METADATA_SELECTION=none suppresses, and de-duplication below
#      would orphan many more.
#
#   2. Drop every property except syft:cpe23.
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
#      components whose primary CPE guess is wrong.
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

def keepprops:
  [ (.properties // [])[] | select(.name == "syft:cpe23") ];

del(.dependencies)
| .components |= (
    group_by(.purl // ([.name, .version, .type] | tostring))
    | map(
        reduce .[] as $c ({};
          if (. | length) == 0 then
            ($c | .properties = keepprops)
          else
              .licenses           = (((.licenses           // []) + ($c.licenses           // [])) | unique)
            | .externalReferences = (((.externalReferences // []) + ($c.externalReferences // [])) | unique)
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
        | if (.properties         | length) == 0 then del(.properties)         else . end
      )
  )
