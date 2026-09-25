# CKAN 2.7 Solr core on a native arm64 base.
#
# The approved `ckan/ckan-solr:2.7` image is amd64-only and its bundled JVM
# (OpenJDK 8) hangs under qemu-user emulation on ARM hosts. `solr:6.6.5` is
# the same Solr 6 line and has an arm64 manifest, so we bake CKAN's core
# config (extracted verbatim from ckan/ckan-solr:2.7) onto it.
# On x86 hosts this builds an amd64 image; on ARM an arm64 one — portable.
FROM solr:6.6.5
COPY --chown=solr:solr ckan /opt/solr/server/solr/ckan
