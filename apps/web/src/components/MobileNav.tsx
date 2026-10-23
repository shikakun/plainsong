import { ExternalLink, MenuIcon } from 'lucide-react';
import { Button } from '@/components/ui/button';
import {
  Sheet,
  SheetClose,
  SheetContent,
  SheetHeader,
  SheetTitle,
  SheetTrigger,
} from '@/components/ui/sheet';
import { cn } from '@/lib/utils';

export interface MobileNavItem {
  href: string;
  slug: string;
  label: string;
  current: boolean;
  external?: boolean;
}

export interface MobileNavProps {
  title: string;
  homeHref: string;
  navLabel: string;
  legalNavLabel: string;
  openLabel: string;
  newTabLabel: string;
  items: ReadonlyArray<MobileNavItem>;
  legalItems: ReadonlyArray<MobileNavItem>;
}

function NavLinkList({
  ariaLabel,
  items,
  newTabLabel,
  className,
}: {
  ariaLabel: string;
  items: ReadonlyArray<MobileNavItem>;
  newTabLabel: string;
  className?: string;
}) {
  return (
    <nav aria-label={ariaLabel} className={cn('flex flex-col gap-1 p-3', className)}>
      {items.map((item) => (
        <SheetClose
          key={item.slug}
          render={
            <a
              href={item.href}
              data-nav-slug={item.external ? undefined : item.slug}
              target={item.external ? '_blank' : undefined}
              rel={item.external ? 'noopener noreferrer' : undefined}
              aria-current={item.current ? 'page' : undefined}
              className={cn(
                'inline-flex items-center gap-1.5 rounded-lg px-3 py-2 text-sm font-medium transition-colors',
                item.current
                  ? 'bg-muted text-foreground'
                  : 'text-muted-foreground hover:bg-muted hover:text-foreground',
              )}
            />
          }
        >
          {item.label}
          {item.external ? (
            <>
              <ExternalLink className="size-3.5 opacity-70" aria-hidden="true" />
              <span className="sr-only">{newTabLabel}</span>
            </>
          ) : null}
        </SheetClose>
      ))}
    </nav>
  );
}

export function MobileNav({
  title,
  homeHref,
  navLabel,
  legalNavLabel,
  openLabel,
  newTabLabel,
  items,
  legalItems,
}: MobileNavProps) {
  return (
    <Sheet>
      <SheetTrigger
        render={
          <Button variant="ghost" size="icon-sm" className="md:hidden" aria-label={openLabel} />
        }
      >
        <MenuIcon />
      </SheetTrigger>
      <SheetContent side="right" className="w-[min(100%,20rem)] gap-0 p-0">
        {/* 閉じるボタン（top-3 right-3、size-7）と上下の端と外側の余白を揃える */}
        <SheetHeader className="p-3">
          <SheetTitle className="flex">
            <SheetClose render={<a href={homeHref} data-nav-slug="" className="flex rounded-md" />}>
              <img
                src="/icon.svg"
                width="28"
                height="28"
                alt={title}
                className="block size-7 rounded-md"
              />
            </SheetClose>
          </SheetTitle>
        </SheetHeader>
        <div className="flex min-h-0 flex-1 flex-col">
          <NavLinkList ariaLabel={navLabel} items={items} newTabLabel={newTabLabel} />
          <NavLinkList
            ariaLabel={legalNavLabel}
            items={legalItems}
            newTabLabel={newTabLabel}
            className="mt-auto"
          />
        </div>
      </SheetContent>
    </Sheet>
  );
}
