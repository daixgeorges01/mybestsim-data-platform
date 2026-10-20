"""Mule 4.7.x standalone launcher fix for Windows installs whose path contains spaces.

conf/java11-plus/wrapper.jvmDependant.conf declares --module-path without quotes, so the JVM fails with
"Module org.mule.boot.tanuki not found" (4.9.x quotes it). This quotes the value and replaces the
%WRAPPER_PATH_SEPARATOR% placeholder. Idempotent. Usage: python patch_mule47_launcher.py <MULE_HOME>
"""
import sys
from pathlib import Path

conf = Path(sys.argv[1]) / "conf" / "java11-plus" / "wrapper.jvmDependant.conf"
text = conf.read_text()
if "stripquotes" in text:
    sys.exit(0)
start = text.index("wrapper.java.additional.<n1>=")
end = text.index("wrapper.java.additional.<n2>")
text = (text[:start]
        + 'wrapper.java.additional.<n1>=--module-path="%MULE_HOME%/lib/boot;%MULE_HOME%/lib/boot/tanuki"\n'
        + "wrapper.java.additional.<n1>.stripquotes=TRUE\n"
        + text[end:])
conf.write_text(text)
print("patched", conf)
