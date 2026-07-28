import { defineConfig } from 'vitepress'

export default defineConfig({
  ignoreDeadLinks: true,
  base: '/azurelocal-vm-conversion-toolkit/',
  title: "Azure Local VM Conversion Toolkit",
  description: "Governed centrally by HCS Platform Engineering standards",
  themeConfig: {
    logo: '/assets/images/azurelocal-vm-conversion-toolkit-icon.svg',
    nav: [{"link":"/","text":"Home"},{"link":"/getting-started","text":"Getting Started"},{"link":"/gen1-vs-gen2","text":"Gen 1 vs Gen 2"},{"link":"/prerequisites","text":"Prerequisites"},{"items":[{"link":"/runbook-azurelocal","text":"Azure Local Path"},{"link":"/runbook-hyperv","text":"Hyper-V Path"}],"text":"Runbooks"},{"link":"/troubleshooting","text":"Troubleshooting"},{"items":{"link":"/reference/variables","text":"Variable Reference"},"text":"Reference"},{"link":"/contributing","text":"Contributing"}],
    sidebar: [{"link":"/","text":"Home"},{"link":"/getting-started","text":"Getting Started"},{"link":"/gen1-vs-gen2","text":"Gen 1 vs Gen 2"},{"link":"/prerequisites","text":"Prerequisites"},{"text":"Runbooks","items":[{"link":"/runbook-azurelocal","text":"Azure Local Path"},{"link":"/runbook-hyperv","text":"Hyper-V Path"}],"collapsed":false},{"link":"/troubleshooting","text":"Troubleshooting"},{"text":"Reference","items":{"link":"/reference/variables","text":"Variable Reference"},"collapsed":false},{"link":"/contributing","text":"Contributing"}],
    socialLinks: [
      { icon: 'github', link: 'https://github.com/AzureLocal/azurelocal-vm-conversion-toolkit' }
    ],
    footer: {
      message: 'Released under the MIT License.',
      copyright: 'Copyright © Hybrid Cloud Solutions & AzureLocal'
    }
  }
})




