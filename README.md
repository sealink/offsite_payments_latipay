# Offsite Payments

Offsite Payments is an extraction from the ecommerce system [Shopify](http://www.shopify.com). Shopify's requirements for a simple and unified API to handle dozens of different offsite payment pages (often called hosted payment pages) with very different exposed APIs was the chief principle in designing the library.

It was developed for usage in Ruby on Rails web applications and integrates seamlessly
as a Rails plugin. It should also work as a stand alone Ruby library, but much of the benefit is in the ActionView helpers which are Rails-specific.

This gem provides integration for [Latipay Payments](https://www.latipay.net/)
through the Offsite Payments gem.

## Installation

### From Git

You can check out the latest source from git:

    git clone https://github.com/sealink/offsite_payments_latipay.git

### From RubyGems

Installation from RubyGems:

    gem install offsite_payments_latipay

Or, if you're using Bundler, just add the following to your Gemfile:

    gem 'offsite_payments_latipay'

## Misc.

- This library is MIT licensed.
