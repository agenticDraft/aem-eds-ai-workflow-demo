Practical things to know about EDS

https://www.youtube.com/watch?v=wuar8WnkVYU 

C

Reuse content across page in different components, for example filter view, search, main blog.

Image 6 
eds-docs/6.EDS_reusing_same_content_in_different_components.png


Option 1:
Let's say so let's say for example you have a blog
detail page with an image, a title, some text. you might want to use this content of this detail page also like here in in a filter view or in the search and for this kind of thing to reuse the content there are a lot of possibilities how to solve this within EDS and one feature is the query index which we think is pretty important and also acts to a certain degree as a backend replacement so when you have this use case let's say and you have this content here you can specify in a helix query yaml file. You can say every time when a page is published to extract certain content out of this page and store it in a query index JSON file. So on publication the data of this page is extracted and stored in this JSON file and then other blocks can consume the data out of this JSON and this way you can share the content and reuse it.

Option 2:
you can you can use fragments in EDS to load on the client a full published page in a block.

Option 3:
experimental feature that
you can use the Adobe experience manager content fragments and directly embed HTML out of these fragments with the HTML write HTML structures in your page where you need this where you need this. Yeah. So you the good thing is when you have to to reuse content across the page you can think about the right uh strategy to do this.

Architecture called "repuls" slajd 11, 12, 13

EDS is Headless frontend project only, which consume external API and micorservices

Our im up command is repuls because we are developing without a heavy local AEM repository or JCR. But the second and more powerful meaning is that is an:
==>>> architecture one code base many sites 

In a traditional model, if your organization has 50 similar micro sites, maybe for different products or regions, you might need 50 different GitHub repositories to manage them. This is a maintenance nightmare.
41:02
I source this for you. You have one base site that is connected to your one and only GitHub repository and then you can create new repololis sites that reuse the exact same codebase but point to
their own separate content sources like different SharePoint folders or different Google Drive. You can even mix it up. Um imagine you need to add a new privacy banner. Instead of deploying that code
50 times, you will only push it once to the main code repository and 
instantly comes available to for all other all other 50 pages.
This massively simplifies code maintenance, ensures 100% brand and functional consistency across all pages and it's incredibly scalable. And the best thing actually is that it's  all managed via configuration and admin API making it a very lightweight and
modern way to manage a large portfolio of sites.

So uh let's quickly talk about what EDS is and what it's not.
First and foremost, EDS is a clean break from classic IM (AEM). It's not an upgrade to your existing IM instance. As I noted on the slide, you cannot and should not try to um reuse any of your legacy IM components. Your site, your HTL, your 
sling models, they have no place in EDS. 

EDS is a completely new separate headless presentation layer. This is a net new front-end project. That leads directly to the second point. As you correctly identified, EDS is architectured as a headless presentation layer. It's the so-called edge. It's not a back-end application server. Complex stateful business logic. Think about a shopping cart, a price calculation engine, or complex user authentication. That logic must be built outside of EDS.
It should live in an external micros service or APIs which EDS ex is ex is extremely good uh to consume at.
The next point is a more specific technical consideration. The DS blockbased system is built on a composition model. You build small simple independent blocks and compose them to create rich pages. It does not have a deep multi-level inheritance model like you might be used to uh use in a classic IM or other object-oriented systems. It's a basically a flatter s simpler and more web native approach. And finally, this isn't really a limitation at all, but it's the most critical consideration for project planning and resourcing. An EDS project is a pure front-end project.

The primary development works work is in HTML, CSS and JavaScript. The main skill
set you need is a strong front-end team and not a team of classic IM Java developers. Your Java experts will be building um the APIs that EDS can consume, usually not working on the EDS project itself. So to summarize, it's a clean break.
It's a headless front end and it requires a front-end team. Knowing this day one is the key to scoping and staffing your project correctly.

I would like to to jump in here and ask you something. So we we know that headless and composable CMS or DXP are clearly in the trend, but we also learned um that EDS is not really a headless CMS.

When to choose EDS:
EDS is for content driven webistes
Agile environment
Custom layout and UX
What you see what you get
Good web performance
Development should be fast and easy

Google can crawl and index EDS pages, headless is not a problem for SEO since content is visible and crawl can run javascript.

Can you any plugins, third party integrations, or custom components be used in EDS? Just make sure for performance and security reasons that you are not loading any heavy libraries or frameworks that are not needed for your project. EDS is designed to be lightweight and fast, so it's important to keep that in mind when adding additional functionality.

Testing, how does this work in EDS?

It's probably standard integration testing or something like that. 
For each change uh there is an a dedicated branch and um this is where you basically do the testing. So QA members test on that branch to see if the integration that you did there or the feature change uh works as expected.

Um on top of that there's like the intermediate layer where you can use the preview environment uh to to publish content variations um that should not necessarily go to production. So you can check publish to preview and test that preview data content with a feature branch.

Can you also run the automated integration tests there?

Uh the automated integration tests. Well, there's like what what what you can do is you can utilize GitHub's um uh actions to to run whenever you do a pull request or a merge request, you can run the automated tests. So you can set up a pipeline that runs the tests on every change and then you can see if the tests pass or fail. If they fail, you can fix the issues before merging the changes into the main branch.