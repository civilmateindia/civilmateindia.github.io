const fs = require('fs');
const path = require('path');
const dir = '.';

const files = fs.readdirSync(dir).filter(f => f.endsWith('.html'));

files.forEach(file => {
    let content = fs.readFileSync(file, 'utf8');
    
    // Check if we need to insert Pricing and Presentations
    if (content.includes('faq.html') && !content.includes('Pricing')) {
        content = content.replace(
            /<a href="faq.html">FAQ<\/a>/g,
            '<a href="pricing.html">Pricing</a>\n            <a href="presentations.html">Presentations</a>\n            <a href="faq.html">FAQ</a>'
        );
        fs.writeFileSync(file, content, 'utf8');
        console.log('Updated', file);
    }
});
