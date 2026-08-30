import clsx from 'clsx';
import Link from '@docusaurus/Link';
import useDocusaurusContext from '@docusaurus/useDocusaurusContext';
import Layout from '@theme/Layout';

import Heading from '@theme/Heading';
import styles from './index.module.css';

function HomepageHeader() {
  const {siteConfig} = useDocusaurusContext();
  return (
    <header className={clsx('hero hero--primary', styles.heroBanner)}>
      <div className="container">
        <Heading as="h1" className="hero__title">
          {siteConfig.title}
        </Heading>
        <p className="hero__subtitle">{siteConfig.tagline}</p>
        <div className={styles.buttons}>
          <Link
            className="button button--secondary button--lg"
            to="/docs/">
            Get Started →
          </Link>
        </div>
      </div>
    </header>
  );
}

function MigrationSteps() {
  const steps = [
    {num: '1', title: 'Prepare', desc: 'Confirm cluster access, Kubernetes version, existing compute, and VPC layout.', to: '/docs/prepare'},
    {num: '2', title: 'Tag Resources', desc: 'Tag subnets and the node security group for Karpenter discovery.', to: '/docs/tag-resources'},
    {num: '3', title: 'Create IAM Role', desc: 'Create node and controller IAM roles with correct trust and permission policies.', to: '/docs/create-iam-role'},
    {num: '4', title: 'Install Karpenter', desc: 'Install Karpenter via Helm from the ECR public registry.', to: '/docs/install-karpenter'},
    {num: '5', title: 'EC2NodeClass & NodePool', desc: 'Define what Karpenter should launch: AMI, subnets, security groups, and instance requirements.', to: '/docs/create-nodeclass-nodepool'},
    {num: '6', title: 'Test & Migrate', desc: 'Verify provisioning works and confirm the final migrated state.', to: '/docs/test-and-migrate'},
  ];

  return (
    <section className={styles.features}>
      <div className="container">
        <div className="row" style={{marginTop: '2rem', marginBottom: '1rem'}}>
          <div className="col col--12" style={{textAlign: 'center'}}>
            <Heading as="h2">Migration Steps</Heading>
            <p>A six-step process from Cluster Autoscaler to Karpenter, fully documented with real commands and outputs.</p>
          </div>
        </div>
        <div className="row">
          {steps.map(({num, title, desc, to}) => (
            <div key={num} className={clsx('col col--4')} style={{marginBottom: '1.5rem'}}>
              <div className="card" style={{height: '100%', padding: '1.5rem'}}>
                <div style={{fontSize: '2rem', fontWeight: 'bold', color: 'var(--ifm-color-primary)', marginBottom: '0.5rem'}}>
                  {num}
                </div>
                <Heading as="h3" style={{marginBottom: '0.5rem'}}>{title}</Heading>
                <p style={{flex: 1}}>{desc}</p>
                <Link className="button button--outline button--primary button--sm" to={to}>Read more →</Link>
              </div>
            </div>
          ))}
        </div>
        <div className="row" style={{marginTop: '1rem', marginBottom: '2rem'}}>
          <div className="col col--12" style={{textAlign: 'center'}}>
            <Link className="button button--secondary button--lg" to="/docs/troubleshooting">
              🔧 Troubleshooting Guide
            </Link>
          </div>
        </div>
      </div>
    </section>
  );
}

export default function Home() {
  const {siteConfig} = useDocusaurusContext();
  return (
    <Layout
      title={siteConfig.title}
      description="Step-by-step migration guide from EKS Cluster Autoscaler to Karpenter, with real commands and outputs.">
      <HomepageHeader />
      <main>
        <MigrationSteps />
      </main>
    </Layout>
  );
}
