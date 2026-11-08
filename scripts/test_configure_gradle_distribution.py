import unittest
from configure_gradle_distribution import configure, KNOWN

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

if __name__ == '__main__': unittest.main()
