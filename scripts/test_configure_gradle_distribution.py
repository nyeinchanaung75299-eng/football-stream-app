import unittest
from configure_gradle_distribution import configure, KNOWN, kotlin_init

class GradleDistributionTests(unittest.TestCase):
    def test_version_settings_and_checksum_are_preserved_or_verified(self):
        original = 'distributionBase=GRADLE_USER_HOME\ndistributionUrl=https\\://services.gradle.org/distributions/gradle-9.3.1-all.zip\nzipStorePath=wrapper/dists\n'
        result = configure(original)
        self.assertIn('gradle-9.3.1-bin.zip', result)
        self.assertIn(KNOWN['9.3.1'], result)
        self.assertIn('zipStorePath=wrapper/dists', result)
        self.assertEqual(configure(result), result)
    def test_a_different_archive_cannot_retain_an_incorrect_checksum(self):
        result = configure('distributionUrl=https://services.gradle.org/distributions/gradle-9.3.1-all.zip\ndistributionSha256Sum=wrong\n')
        self.assertNotIn('wrong', result)
        with self.assertRaises(ValueError): configure('distributionUrl=unversioned')
    def test_verified_maven_override_is_limited_to_the_exact_compiler_version(self):
        result=kotlin_init('file:///tmp/verified-maven')
        self.assertIn("includeVersion('org.jetbrains.kotlin', 'kotlin-compiler-embeddable', '2.2.21')",result)
        self.assertNotIn('includeGroup',result)
        self.assertIn('project.buildscript.repositories',result)

if __name__ == '__main__': unittest.main()
