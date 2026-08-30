// @ts-check

// This runs in Node.js - Don't use client-side code here (browser APIs, JSX...)

/**
 * Creating a sidebar enables you to:
 - create an ordered group of docs
 - render a sidebar for each doc of that group
 - provide next/previous navigation

 The sidebars can be generated from the filesystem, or explicitly defined here.

 Create as many sidebars as you want.

 @type {import('@docusaurus/plugin-content-docs').SidebarsConfig}
 */
const sidebars = {
  migrationSidebar: [
    'intro',
    {
      type: 'category',
      label: 'Migration Steps',
      collapsed: false,
      items: [
        'prepare',
        'tag-resources',
        'create-iam-role',
        'install-karpenter',
        'create-nodeclass-nodepool',
        'test-and-migrate',
      ],
    },
    'troubleshooting',
  ],
};

export default sidebars;
